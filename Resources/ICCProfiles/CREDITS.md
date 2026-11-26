# Bundled ICC output profiles

The CMYK output profiles in this folder come from the ICC Profile Registry. Both terms were read on the registry pages on 26 November 2026, the day the files were downloaded. Paper & Grain ships the files unaltered, copies them into a book package only when the author chooses them, and embeds them in the author's PDFs as the output intent, which the terms allow. Neither file is sold. The SHA-256 of each file is fixed in `ICCProfileSources.bundled` and checked before use.

| File | Holder | Terms (registry page) | SHA-256 |
|---|---|---|---|
| `GRACoL2006_Coated1v2.icc` | Idealliance, with permission of X-Rite, Inc. | "This profile is made available by IDEAlliance, with permission of X-Rite, Inc., and may be used, embedded, exchanged, and shared without restriction. It may not be altered, or sold without written permission of IDEAlliance." <https://registry.color.org/profile-registry/GRACoL2006_Coated1v2> | `7f822b354f3f4081e3b1dadd381c9f16d583257d1574e583be7d0e3433a6b45b` |
| `Coated_Fogra39L_VIGC_300.icc` | VIGC (<http://www.vigc.be>), with permission of X-Rite, Inc. | "This profile is made available by VIGC, with permission of X-rite, and may be used, embedded, exchanged, and shared without restriction. It may not be altered or sold without written permission of VIGC" <https://registry.color.org/profile-registry/Coated_Fogra39L_VIGC_300> | `6df43849a84d2632e7900a125f657bd09364ed56775bc4740c1e39a5492d47e3` |

Notes:

- The registry lists the GRACoL profile's ID as `a8866753231033716e922384e46e2369`; the downloaded file's header carries an all-zero profile ID, so the app checks the SHA-256, not the ID.
- PSO Coated v3 (ECI) is not in this folder: its terms do not allow distribution. The app downloads it from eci.org on the author's click and checks the SHA-256 fixed in `ECIProfile.expectedSHA256`.
