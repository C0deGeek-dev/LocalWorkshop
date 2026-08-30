@{
    # Curated gate for LocalWorkshop pipeline scripts. Everything not excluded
    # below is blocking. Prefer point fixes / scoped SuppressMessage with a
    # written justification over new exclusions.
    #
    # Excluded by design (these are interactive build CLIs, not a library):
    #   PSAvoidUsingWriteHost            - console progress is the product surface
    #   PSUseShouldProcessForStateChangingFunctions - acquire/convert/quantize
    #                                      manage tool-owned files + processes
    #   PSUseSingularNouns, PSUseApprovedVerbs - shipped verbs/nouns are stable
    #   PSUseOutputTypeCorrectly         - informational noise here
    #   PSUseBOMForUnicodeEncodedFile    - files are UTF-8 without BOM, PowerShell 7+
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        'PSUseApprovedVerbs',
        'PSUseOutputTypeCorrectly',
        'PSUseBOMForUnicodeEncodedFile'
    )
}
