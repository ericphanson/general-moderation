# 3-Letter Package Name Categories

This document defines mutually exclusive categories for all 3-letter package registration attempts in the Julia General Registry.

## Category Assignment Rules

Each package must be assigned to **exactly ONE** category based on the following decision tree (apply in order):

### Priority 1: Technical/Process Issues
If the package was closed for technical reasons unrelated to the name itself:
- **Category: Technical Rejection**

### Priority 2: Accepted Packages (in order of specificity)

1. **Library Wrapper**
   - Criteria: Package wraps an existing external library/tool with the same 3-letter name
   - Evidence: Discussion mentions "wrapper" or similar, or justifications include "library_wrapper"
   - Examples: ITK (wraps ITK library), KLU (wraps KLU solver), XCB (wraps XCB)

2. **Pre-existing/Grandfathered**
   - Criteria: Package existed before the naming guidelines were enforced
   - Evidence: Discussion explicitly mentions "pre-existing", "established", or "grandfathered"
   - Must have explicit exemption claim in discussion
   - Examples: AWS (explicitly exempted as pre-existing)

3. **Standard File Format**
   - Criteria: Represents a widely-recognized standard file format
   - Evidence: Package deals with file I/O for a standard format (XML, JSON-like, etc.)
   - Must be a recognized standard, not just any file format
   - Examples: XML, EDF (European Data Format), TCX (Training Center XML), KML (Keyhole Markup Language)

4. **Domain-Specific Acronym**
   - Criteria: Acronym is widely known within a specific technical domain (not just to the author)
   - Evidence: Justifications include "domain_specific_acronym" OR maintainer explicitly acknowledges the acronym is widely understood in that field
   - Examples: AES (Advanced Encryption Standard), SMC (Sequential Monte Carlo)

5. **Company/Brand Name**
   - Criteria: 3-letter name represents official company/organizational branding
   - Evidence: Discussion explicitly mentions branding or company name consistency
   - Very rare - only for cases with explicit branding justification
   - Examples: RAI (RelationalAI)

6. **Discretionary Approval**
   - Criteria: Merged without any special exemption category above
   - Evidence: Has "minimum_length_satisfied" justification OR merged with minimal discussion
   - Catch-all for approved packages that don't fit other categories
   - Often from earlier time periods (2019-2021)
   - Examples: Run, Try, Air, Jin

### Priority 3: Rejected Packages (in order)

7. **Duplicate/Superseded PR**
   - Criteria: PR was closed because another PR was opened (duplicate registration attempt)
   - Evidence: Comment says "Closing in favor of #XXXXX" or similar
   - Very common pattern
   - Examples: Any PR closed with "superseded by" message

8. **Rejected: Acronym Not Widely Known**
   - Criteria: Explicitly rejected because the acronym is domain jargon not widely understood
   - Evidence: Discussion mentions "acronym", "jargon", "not widely known", "avoid acronyms", or suggests longer descriptive name
   - Most common substantive rejection reason
   - Examples: AME, BEE, INT, HGF, NMR

9. **Rejected: Poor Discoverability**
   - Criteria: Rejected due to search/Google-ability concerns
   - Evidence: Discussion mentions "google", "search", "find", "discoverability"
   - Examples: RIM (can't google it), Phi

10. **Rejected: Name Collision/Ambiguity**
    - Criteria: Name conflicts with existing package or has multiple common meanings
    - Evidence: Discussion mentions similarity to other packages, confusion, or multiple meanings
    - Examples: CGA (conflicts with Conformal Geometric Algebra), Dsp (conflicts with DSP)

11. **Technical Rejection**
    - Criteria: PR closed due to technical issues unrelated to package name
    - Evidence: Missing license, compat issues, build failures, repo URL problems
    - Check violations for: missing_compat, repo_url, install_load_failure, version issues
    - Examples: Packages with technical violations but minimal name discussion

12. **Rejected: Generic/Other**
    - Criteria: Rejected but doesn't fit any specific rejection category above
    - Last resort catch-all for rejections
    - Should be minimized after careful review

## Category Assignment Process

For each package:

1. Check if it was merged → If YES, go to Accepted categories (2-6)
2. Check if it was rejected for technical reasons → If YES, assign "Technical Rejection"
3. Check Accepted categories in order (1→6), assign to first match
4. Check Rejected categories in order (7→10), assign to first match
5. If no match found, assign to catch-all (Discretionary Approval if merged, Generic Rejection if not)

## Evidence Requirements

For each categorized package, provide:
- **category**: The category name
- **proof**: A key quote from discussion or violation message that justifies the category
- **proof_path**: Path to the JSON file containing the evidence (either `data/X/PKG-prNNNN.json` or `analysis/X/PKG-prNNNN-analysis.json`)

## Notes

- Pre-2022 packages have higher discretionary approval rates
- Wrapper status is determinative even if violations exist
- Violations can be overridden with sufficient justification
- Time period matters: 2019 (61% acceptance) → 2023+ (6% acceptance)
