# Third-party notices

## oxipng 10.2.1

MacCare statically links oxipng into its Rust engine with default features disabled.
Source: https://github.com/oxipng/oxipng/tree/v10.2.1
The upstream MIT license and licenses/notices of its pinned dependency tree are
preserved in `app/vendor/oxipng` and copied to `Contents/Resources/oxipng`.
The locked versions are in `core/Cargo.lock`; `manifest.json` maps source and notices.
The integration only recompresses PNG copies and preserves original files.

## smartmontools 7.5 (r5714)

MacCare bundles the unmodified upstream smartctl program, narrowed to the app
architecture and re-signed. It is a separate process, used only for read-only
health information. No smartd service, installer scripts or kernel drivers are installed.
Source: https://github.com/smartmontools/smartmontools/tree/RELEASE_7_5
GPLv2-or-later COPYING, AUTHORS, the drive database, the exact corresponding
upstream source archive and pinned provenance are supplied in
`Contents/Resources/smartmontools`. The source archive includes build instructions.

## mas 7.0.0

MacCare embeds the official mas executable to detect Mac App Store updates
without Homebrew. Source: https://github.com/mas-cli/mas/tree/v7.0.0
The upstream MIT license is preserved in `app/vendor/mas/LICENSE`, alongside
the licenses of its pinned Swift dependencies and their source revisions.
These notices are copied into `MacCare.app/Contents/Resources/mas/`.
The executable is re-signed with MacCare's identity, without source changes.
MacCare only invokes `outdated --inaccurate --json`; users install app updates
in the App Store. The upstream executable uses Apple's private frameworks,
so compatibility with future macOS versions is not guaranteed.

## Sparkle 2.10.1

MacCare embeds Sparkle, the BSD-licensed macOS software update framework.
Source: https://github.com/sparkle-project/Sparkle
The full Sparkle license and third-party notices are copied unchanged into
`MacCare.app/Contents/Resources/Sparkle-LICENSE` and remain in the framework.

## SMC wire structure — SMCKit

The SMC message wire layout in `app/Sources/CMacCareSMC/MacCareSMC.c` is adapted
from SMCKit. The rest of the battery policy, watchdog, UI and restricted hardware
interface is implemented for MacCare.

Source: https://github.com/beltex/SMCKit
Also observed in the MIT-licensed SMC.swift included in the public AlDente tree,
commit `8b93da203592f4ad2e9f09fc9cfd2a77b0997de6`.

The MIT License

Copyright (C) 2014-2017 beltex <https://beltex.github.io>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## AlDente technical reference

https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring

The public Helper.swift at the same commit demonstrates the CH0B byte values
0 (allow charging) and 2 (inhibit charging). It was consulted as a technical
reference. No AlDente implementation, artwork, strings, helper binary or
commercial functionality is bundled with MacCare. The AlDente repository's
current root LICENSE is an evaluation agreement, not a general open-source
license. It does not replace the separate MIT notice on the SMCKit component.

Additional technical reference for the paired CH0B/CH0C gates and the four-byte
CHTE gate on newer firmware:
https://github.com/charlie0129/batt/blob/master/pkg/smc/charging.go
https://github.com/charlie0129/batt/blob/master/pkg/smc/consts_arm64.go
The same reference documents bfF0/bfD0/bfE0, their little-endian encoding and
required disable/upper/lower/activate order for firmware-managed bands.
Only register semantics were consulted; no Go implementation is included.

Battery telemetry technical reference (IOPS internal battery selection,
AppleSmartBatteryPack and temperature units):
https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift
Only interface/property semantics were consulted; no Stats implementation is bundled.

GPU sensor identifiers for the M1 generation (`Tg05`, `Tg0D`, `Tg0L`, `Tg0T`)
were cross-checked against the Stats sensor catalog, commit
`a04bc5e629242c9a29a98ef32ed1f5f46a88c874`:
https://github.com/exelban/stats/blob/a04bc5e629242c9a29a98ef32ed1f5f46a88c874/Modules/Sensors/values.swift
The type-0 read-only SMC connection was checked against `SMC/smc.swift` in the
same project. Only sensor identifiers and interface semantics were consulted;
no additional Stats implementation is bundled.

## Native charge policy technical reference

The root preference domain, its two manual charge-limit keys, the reload
notification and the need to release the agent's registration were cross-checked
against the MIT-licensed Ampere project, commit
`843498d7beb711c0e1b18e48c8520debe67f6e3f`:
https://github.com/az-code-lab/ampere
https://github.com/az-code-lab/ampere/blob/843498d7beb711c0e1b18e48c8520debe67f6e3f/LICENSE
MacCare's driver, typed recovery record and verification are independently implemented.
