# Three-Letter Package Names in Julia Registry

**Generated:** 2025-11-12T04:27:58.928
**Total 3-letter packages found:** 46

## Summary

- **Merged:** 46
- **Not merged (closed):** 0
- **With analysis:** 46
- **Without analysis:** 0

---

## All 3-Letter Packages

| Package | PR # | Status | Comments | Merged By | Key Reviewer | Comment | Data | Analysis |
|---------|------|--------|----------|-----------|--------------|---------|------|----------|
| ADI | #19070 | ✅ Merged | 2 | @fredrikekre | — | — | [JSON](data/A/ADI-pr19070.json) | [Analysis](analysis/A/ADI-pr19070-analysis.json) |
| AES | #13857 | ✅ Merged | 4 | @DilumAluthge | @DilumAluthge | I would recommend a longer name.<br><br>That being said, it is your package. | [JSON](data/A/AES-pr13857.json) | [Analysis](analysis/A/AES-pr13857-analysis.json) |
| AWS | #20506 | ✅ Merged | 24 | @fredrikekre | @oxinabox | This package should be exempt to the 5 letter rule as it is a pre-existing package with a name from long before that guideline that is only now being updated to be Julia 1.0 compatible. | [JSON](data/A/AWS-pr20506.json) | [Analysis](analysis/A/AWS-pr20506-analysis.json) |
| Air | #47025 | ✅ Merged | 4 | @fredrikekre | @JuliaRegistrator | An unexpected error occurred during registration. | [JSON](data/A/Air-pr47025.json) | [Analysis](analysis/A/Air-pr47025-analysis.json) |
| Amb | #2054 | ✅ Merged | 2 | @fredrikekre | @StefanKarpinski | Needs compat, at least for Julia itself. | [JSON](data/A/Amb-pr2054.json) | [Analysis](analysis/A/Amb-pr2054-analysis.json) |
| Ant | #1095 | ✅ Merged | 6 | @StefanKarpinski | @StefanKarpinski | Up to you. If you want to go with `Ant` that's ok too. Just retrigger when you're ready. | [JSON](data/A/Ant-pr1095.json) | [Analysis](analysis/A/Ant-pr1095-analysis.json) |
| CAP | #118365 | ✅ Merged | 8 | @carstenbauer | @carstenbauer | I agree with @goerz in that we should merge this although it's not optimal.<br><br>But one more question: Can we expect this to be the last short acronym named package from this area for the foreseeable future? | [JSON](data/C/CAP-pr118365.json) | [Analysis](analysis/C/CAP-pr118365-analysis.json) |
| EDF | #3650 | ✅ Merged | 3 | @StefanKarpinski | @fredrikekre | Please add (at least)<br>```<br>[compat]<br>julia = "1"<br>```<br>to your project file and retrigger the bot. | [JSON](data/E/EDF-pr3650.json) | [Analysis](analysis/E/EDF-pr3650-analysis.json) |
| FIB | #21383 | ✅ Merged | 1 | @DilumAluthge | — | — | [JSON](data/F/FIB-pr21383.json) | [Analysis](analysis/F/FIB-pr21383-analysis.json) |
| FMI | #37533 | ✅ Merged | 8 | @ericphanson | @ericphanson | Ok, let's do it | [JSON](data/F/FMI-pr37533.json) | [Analysis](analysis/F/FMI-pr37533-analysis.json) |
| Fri | #5330 | ✅ Merged | 7 | @fredrikekre | @fredrikekre | FYI: https://julialang.github.io/Pkg.jl/v1/creating-packages/#Package-naming-guidelines-1<br><br>I see that this is a port of a `fri` python package, so it might make sense, although Julia packages are almost exclusively spelled with capital letters.<br><br>[noblock] | [JSON](data/F/Fri-pr5330.json) | [Analysis](analysis/F/Fri-pr5330-analysis.json) |
| GAP | #893 | ✅ Merged | 4 | @fredrikekre | @fredrikekre | Can you add<br>```toml<br>[compat]<br>julia = "1.1"<br>```<br>to your project file and retrigger the bot? | [JSON](data/G/GAP-pr893.json) | [Analysis](analysis/G/GAP-pr893-analysis.json) |
| Gen | #15310 | ✅ Merged | 6 | @ViralBShah | @ViralBShah | Will that break something, if we merge it with the version number it has? Clearly the package has earlier history prior to registration - so I'd be ok merging - all else being ok. | [JSON](data/G/Gen-pr15310.json) | [Analysis](analysis/G/Gen-pr15310-analysis.json) |
| Glo | #3291 | ✅ Merged | 1 | @KristofferC | @julia-tagbot | I've created release `v0.1.0`, [here](https://github.com/BeastyBlacksmith/Glo.jl/releases/tag/v0.1.0) it is.<br><!-- 7a81acb0-d20c-11e9-9b00-65826819e9d2 --> | [JSON](data/G/Glo-pr3291.json) | [Analysis](analysis/G/Glo-pr3291-analysis.json) |
| ISL | #37152 | ✅ Merged | 2 | @DilumAluthge | — | — | [JSON](data/I/ISL-pr37152.json) | [Analysis](analysis/I/ISL-pr37152-analysis.json) |
| ITK | #2661 | ✅ Merged | 7 | @fredrikekre | @StefanKarpinski | Given that it's a wrapper for the existing ITK package, the name is 👍 | [JSON](data/I/ITK-pr2661.json) | [Analysis](analysis/I/ITK-pr2661-analysis.json) |
| JDF | #3542 | ✅ Merged | 0 | @fredrikekre | — | — | [JSON](data/J/JDF-pr3542.json) | [Analysis](analysis/J/JDF-pr3542-analysis.json) |
| JET | #33580 | ✅ Merged | 2 | @KristofferC | — | — | [JSON](data/J/JET-pr33580.json) | [Analysis](analysis/J/JET-pr33580-analysis.json) |
| Jin | #49720 | ✅ Merged | 2 | @giordano | — | — | [JSON](data/J/Jin-pr49720.json) | [Analysis](analysis/J/Jin-pr49720-analysis.json) |
| KLU | #49410 | ✅ Merged | 4 | @ChrisRackauckas | @ChrisRackauckas | This name is fine since it matches the standard for wrapper packages, i.e. it's wrapping a package called KLU so KLU.jl is the clear choice. Looks like it's just about time for the 3 day mark so I'll merge. | [JSON](data/K/KLU-pr49410.json) | [Analysis](analysis/K/KLU-pr49410-analysis.json) |
| KML | #61044 | ✅ Merged | 3 | @giordano | — | — | [JSON](data/K/KML-pr61044.json) | [Analysis](analysis/K/KML-pr61044-analysis.json) |
| Ket | #110011 | ✅ Merged | 4 | @ericphanson | @goerz | [noblock] Based on that explanation, I would have no objections to this package being registered under the name `Ket`. I don't have merge permissions, though, so ultimately it'll come down to convincing at least one registry maintainer to merge it manually. If nobody else voices any concerns, you can wait the three-day period, and then ping the `#pkg-registration` channel on Slack again and ask for a merge. | [JSON](data/K/Ket-pr110011.json) | [Analysis](analysis/K/Ket-pr110011-analysis.json) |
| LKH | #30852 | ✅ Merged | 2 | @giordano | — | — | [JSON](data/L/LKH-pr30852.json) | [Analysis](analysis/L/LKH-pr30852-analysis.json) |
| LSL | #4256 | ✅ Merged | 7 | @fredrikekre | @fredrikekre | Can you retrigger to resolve the conflict? Also, how about calling this `LabStreamingLayer` (`LabStreamingLayers`?)<br><br>Edit: nvm, this was wrapping a lsl library. | [JSON](data/L/LSL-pr4256.json) | [Analysis](analysis/L/LSL-pr4256-analysis.json) |
| Lux | #59605 | ✅ Merged | 2 | @giordano | @avik-pal | [noblock] This is a package name change from ExplicitFluxLayers to Lux<br><br>Public Discussion regarding name change -- https://julialang.slack.com/archives/C690QRAA3/p1650979193377099<br><br>cc @giordano  | [JSON](data/L/Lux-pr59605.json) | [Analysis](analysis/L/Lux-pr59605-analysis.json) |
| MKL | #22878 | ✅ Merged | 1 | @giordano | — | — | [JSON](data/M/MKL-pr22878.json) | [Analysis](analysis/M/MKL-pr22878-analysis.json) |
| Mex | #47975 | ✅ Merged | 2 | @giordano | — | — | [JSON](data/M/Mex-pr47975.json) | [Analysis](analysis/M/Mex-pr47975-analysis.json) |
| NES | #3549 | ✅ Merged | 1 | @fredrikekre | @kraftpunk97-zz | @fredrikekre if everything's good, can we proceed with the registration? | [JSON](data/N/NES-pr3549.json) | [Analysis](analysis/N/NES-pr3549-analysis.json) |
| Org | #2292 | ✅ Merged | 3 | @StefanKarpinski | @StefanKarpinski | Sorry for the delayed merge. Didn't notice that this had been updated. | [JSON](data/O/Org-pr2292.json) | [Analysis](analysis/O/Org-pr2292-analysis.json) |
| PWF | #49190 | ✅ Merged | 3 | @giordano | — | — | [JSON](data/P/PWF-pr49190.json) | [Analysis](analysis/P/PWF-pr49190-analysis.json) |
| QML | #18516 | ✅ Merged | 4 | @giordano | @giordano | I think name and version number are all fine. Ping in three days and I'll merge | [JSON](data/Q/QML-pr18516.json) | [Analysis](analysis/Q/QML-pr18516-analysis.json) |
| QOI | #51291 | ✅ Merged | 3 | @KristofferC | — | — | [JSON](data/Q/QOI-pr51291.json) | [Analysis](analysis/Q/QOI-pr51291-analysis.json) |
| QSM | #54243 | ✅ Merged | 2 | @giordano | — | — | [JSON](data/Q/QSM-pr54243.json) | [Analysis](analysis/Q/QSM-pr54243-analysis.json) |
| RAI | #57692 | ✅ Merged | 3 | @giordano | @bradlo | We use the acronym RAI to brand all of our developer materials, including all language SDKs. Our users appreciate the consistency and we think it is more "developer friendly" than using the relatively long company name, RelationalAI. | [JSON](data/R/RAI-pr57692.json) | [Analysis](analysis/R/RAI-pr57692-analysis.json) |
| ROS | #26943 | ✅ Merged | 1 | @giordano | — | — | [JSON](data/R/ROS-pr26943.json) | [Analysis](analysis/R/ROS-pr26943-analysis.json) |
| Run | #18563 | ✅ Merged | 8 | @fredrikekre | @zsunberg | Just noticed this as I was dealing with some of my own package registrations - I would vote for a more descriptive name than "Run" @tkf  :) | [JSON](data/R/Run-pr18563.json) | [Analysis](analysis/R/Run-pr18563-analysis.json) |
| SMC | #2892 | ✅ Merged | 8 | @fredrikekre | @ethanmatlin | We'd like to keep it SMC if possible. We'll make it clear in the description, documentation, and other advertising what it's intended to be used for. Thanks! | [JSON](data/S/SMC-pr2892.json) | [Analysis](analysis/S/SMC-pr2892-analysis.json) |
| SMM | #1536 | ✅ Merged | 9 | @fredrikekre | @fredrikekre | > phew... i had removed a __precompile__(false) without knowing too much about it. all hell broke loose! i think we're ready to go now.<br><br>What happened? Unless you do weird things it should be fine to precompile. maybe you just need to initialize these https://github.com/floswald/SMM.jl/blob/86923918ebc55103a51ce446427130079375bae2/src/SMM.jl#L79-L80 in the `__init__()`?<br><br>(Btw, its a bit weird that your package swaps out the users logger.) | [JSON](data/S/SMM-pr1536.json) | [Analysis](analysis/S/SMM-pr1536-analysis.json) |
| Tar | #6450 | ✅ Merged | 4 | @DilumAluthge | @julia-tagbot | I've created release `v0.1.0`, [here](https://github.com/JuliaLang/Tar.jl/releases/tag/v0.1.0) it is.<br><!-- 1b1a0100-1aa0-11ea-8273-263ef86eb4e3 --> | [JSON](data/T/Tar-pr6450.json) | [Analysis](analysis/T/Tar-pr6450-analysis.json) |
| Try | #57060 | ✅ Merged | 2 | @fredrikekre | — | — | [JSON](data/T/Try-pr57060.json) | [Analysis](analysis/T/Try-pr57060-analysis.json) |
| UCX | #28878 | ✅ Merged | 1 | @vchuravy | — | — | [JSON](data/U/UCX-pr28878.json) | [Analysis](analysis/U/UCX-pr28878-analysis.json) |
| VQC | #3322 | ✅ Merged | 6 | @fredrikekre | @fredrikekre | Please add (at least)<br>```<br>[compat]<br>julia = "1"<br>```<br>to your project file and retrigger the bot. | [JSON](data/V/VQC-pr3322.json) | [Analysis](analysis/V/VQC-pr3322-analysis.json) |
| XCB | #23401 | ✅ Merged | 7 | @giordano | @giordano | > The compat entries were also updated.<br><br>Automerge doesn't think so and [this file](https://github.com/JuliaRegistries/General/blob/0fa5d146ebc1b57e1a1db09de766aa0c3a5938f3/X/XCB/Compat.toml) doesn't have any entry for `CEnum`.  You need to retrigger registration (without changing the version number) so that this pull request is updated | [JSON](data/X/XCB-pr23401.json) | [Analysis](analysis/X/XCB-pr23401-analysis.json) |
| XDF | #20235 | ✅ Merged | 3 | @fredrikekre | — | — | [JSON](data/X/XDF-pr20235.json) | [Analysis](analysis/X/XDF-pr20235-analysis.json) |
| XML | #58359 | ✅ Merged | 3 | @giordano | — | — | [JSON](data/X/XML-pr58359.json) | [Analysis](analysis/X/XML-pr58359-analysis.json) |
| XRT | #114380 | ✅ Merged | 2 | @giordano | @goerz | [noblock] Being a wrapper, the name `XRT` seems okay to me, but it will need a manual merge.<br><br>Of course, the compat-issues have to be fixed. | [JSON](data/X/XRT-pr114380.json) | [Analysis](analysis/X/XRT-pr114380-analysis.json) |
