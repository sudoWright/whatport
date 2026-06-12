# Plan: UUID-anchored port correlation

Status: Phase 1 implemented (2026-06-12). Phases 2 and 3 pending.
Author: scoping pass, 2026-06-12
Context: requested after the charger-port-correlation bug (PR #5), where data
landed on the wrong physical port. We want a stable per-port identity so this
class of bug stops recurring.

## Implementation note (gotcha for Phase 2)

`IORegistryEntryGetName` returns the node name WITHOUT the `@N` suffix (e.g.
`"Port-USB-C"`, not `"Port-USB-C@4"`). The `@N` is the node's
location-in-plane, read via `IORegistryEntryGetLocationInPlane` and parsed as
hex. ioreg only shows `@N` by concatenating the two. Use
`ioLocationInPlaneInt` for the port number, never the name.

## Problem

Today WhatPort ties every data source to a port by a small integer port
number, scraped from a different key per source:

| Data            | IOKit node                  | Join key                                   |
|-----------------|-----------------------------|--------------------------------------------|
| PHY lanes       | `AppleTypeCPhy`             | parent `port-number` (or PHY ID + 1)       |
| Thunderbolt     | `IOThunderboltPort`         | `Socket ID`                                |
| Power out       | `AppleSmartBattery`         | `PortIndex`                                |
| Charger in      | `IOPortFeaturePowerSource`  | `ParentBuiltInPortNumber`                  |
| CC / cable      | `IOPortTransportStateCC`    | `ParentBuiltInPortNumber` + `ParentPortTypeDescription` |
| USB devices     | `IOUSBHostDevice`           | parent `UsbCPortNumber`                    |
| Live transport  | `IOPortTransportState*`     | `ParentBuiltInPortNumber`                  |

Two known hazards with integer keys, both confirmed on the M5 dev machine:

1. **MagSafe / USB-C `@N` collision.** `Port-USB-C@1` and `Port-MagSafe 3@1`
   share the number 1. Today we dodge this by filtering on `portType`. It
   works, but it is a workaround, and it breaks the moment any two same-type
   connectors share a number.
2. **XHCI vs HPM numbering disagreement.** `UsbCPortNumber` (XHCI) and the
   HPM `@N` do not always agree on M3+. A USB device can therefore be tied to
   the wrong physical port. This is a latent bug we have not yet seen surface.

## The identity that fixes it

Every physical port has a stable UUID on its HPM controller node. Confirmed on
the M5:

```
Port-USB-C@1     UUID 6230AF2D-EE59-552E-E28A-652CCC0E7B11
Port-USB-C@2     UUID 492BAF2D-4561-2E29-5FFE-BD2ADE023D0F
Port-USB-C@4     UUID 17BD562D-D913-3441-0CD9-435CAC6CFA51
Port-MagSafe 3@1 UUID 7C30AF2D-CC71-7D20-5287-C77DB8476817
```

Note `@1` USB-C and `@1` MagSafe have different UUIDs: the collision is
resolved at the source.

Key facts (from research/cross-class-identifiers.md and live probing):

- Property key is exactly `"UUID"`.
- It lives on the HPM device node: `AppleHPMDeviceHALType3` (M3+) or base
  `AppleHPMDevice` (all families, incl. M1/M2 and Intel per probe-35: 265/265
  ports carried it). It is NOT on the PHY, TB, SMC, or transport-state nodes.
- The port-interface nodes are `AppleHPMInterfaceType10/11/12/18` (M3+) and
  `AppleTCControllerType10/11` (M1/M2). On the M5: 6 Type10 + 2 Type11
  instances for 3 USB-C + 1 MagSafe physical ports, so the reader must filter
  to real connectors (`PortTypeDescription` USB-C/MagSafe, name `Port-` prefix).
- Absent on desktop front USB-C (Mac mini / Studio): those hang off a plain
  hub with no HPM node. Must degrade gracefully to today's behaviour.

## Important: UUID is a spine, not a universal key

Even WhatCable, which adopted this, does NOT UUID-join everything. The UUID
anchors the **port list** and the transport-state / power-source nodes. These
keep their own keys because the UUID is not reachable on them:

- Thunderbolt stays on `Socket ID` (= `@N`).
- PHY stays on positional index / `port-number`.
- USB devices stay on name match + `locationID`.

So the goal is: make the HPM node the canonical port list, give each port a
UUID identity, and join the sources that benefit (CC, power, transport,
charger) by UUID; the others keep their existing key but resolve onto the same
canonical port.

## Proposed design (layered, matches existing architecture)

### IOKit layer
- New `HPMReader.swift`: enumerate the HPM interface classes, filter to real
  connectors, and for each walk up to the `AppleHPMDevice*` parent to read
  `UUID`. Emit `RawHPMPort { uuid, portNumber, portType, serviceName }`.
- `IOKitHelpers.swift`: add `ioAncestorPropertyMatching(service, key:, classPredicate:, maxDepth:)`
  that walks parents until a node whose class matches the predicate, then
  reads a key. Used to fetch the HPM UUID from any descendant node.
- `PortSnapshot`: add `hpmPorts: [RawHPMPort]`.

### Domain layer
- `PortState`: add `uuid: String?` as the stable identity. Keep `id: Int`
  (port number) for display/labels.
- `PortManagerSnapshot` + inputs: add `hpmPorts: [HPMPortInput]`.
- `correlate()`: build the canonical port list from `hpmPorts` (keyed by UUID)
  instead of from TB socket IDs / PHY port numbers. Join each source onto the
  canonical port:
  - CC / power / charger / transport: by `(portNumber, portType)` resolved to
    the canonical UUID. (These all use `@N`, which agrees with HPM `@N`.)
  - PHY: by `port-number` to the canonical port (unchanged key, canonical target).
  - Thunderbolt: by `Socket ID` == `@N` to the canonical port.
  - USB devices: phase 2 (see below).
  - Fallback: when `hpmPorts` is empty (Intel / desktop front ports), keep the
    current port-number correlation exactly as-is.

### UI layer
- No change. Labels still read the port number; it now comes from the
  canonical list. The UUID is internal.

## Phasing

1. **Phase 1 (the spine).** HPM reader + canonical UUID-keyed port list + map
   existing `@N`/socket-ID/PHY joins onto it. Removes the `portType`
   workaround by construction. Keep full port-number fallback for non-HPM Macs.
2. **Phase 2 (USB device bridge).** Resolve `IOUSBHostDevice` to the canonical
   port by HPM-UUID parent walk (or `locationID`), not `UsbCPortNumber`. Fixes
   the XHCI/HPM numbering mismatch.
3. **Phase 3 (future, optional).** Desktop power-out: bridge the SMC `DxUI`
   channel to the UUID for Mac mini / Studio per-port power. Out of scope now.

## Blast radius

New: `HPMReader.swift`, `HPMPortInput` type, a couple of `IOKitHelpers`
functions, tests for the HPM read and UUID join.

Changed: `PortSnapshot`, `PortManagerSnapshot` + `SnapshotAdapter`, `PortState`
(one field), and the core of `PortManager.correlate()` (the delicate part).
UI untouched.

Risk concentrated in `correlate()`. Mitigations: keep the existing
port-number path as the no-HPM fallback, migrate one source at a time behind
the canonical list, and lean on the existing correlation tests plus new
UUID-collision tests (the M5 `@1` MagSafe/USB-C case makes a perfect fixture).

## Open questions

- Cross-reboot stability of the UUID is untested (WhatCable treats it as a
  within-session key only). Fine for live monitoring; do not persist it.
- M1/M2 path: base `AppleHPMDevice` carries the UUID, but confirm the parent
  walk reaches it from the `AppleTCControllerType10/11` interface nodes before
  relying on it there. Until confirmed, M1/M2 can use the fallback.
