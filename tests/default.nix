{ lib }:
let
  suites = {
    options = import ./options.nix { inherit lib; };
    input = import ./eval.nix { inherit lib; };
    resolver = import ./resolver.nix { inherit lib; };
    compiler = import ./compiler.nix { inherit lib; };
  };
in
suites
// {
  # Guard discovery independently of fixture evaluation. Keep this list explicit:
  # a suite accidentally returning an empty attribute set must not pass unnoticed.
  testSuiteDiscovery = {
    expr = builtins.mapAttrs (_: suite: builtins.attrNames suite) suites;
    expected = {
      options = [
        "testAcceptOperatorPendingKeyMode"
        "testDoNotEvaluatePackageModuleMetadata"
        "testNestedNullAndStartup"
        "testNoSyntheticTriggerConflict"
        "testNullAndExplicitBothOrders"
        "testNullDoesNotHideConflict"
        "testNullTimingDefault"
        "testNullableSchema"
        "testOpaquePackageMetadata"
        "testPreservePackageModuleMetadata"
        "testPreserveRawConflict"
        "testRejectDependencyModuleProperty"
        "testRejectInvalidNestedTools"
        "testRejectInvalidStartup"
        "testRejectKeyModuleProperty"
        "testRejectListModuleProperty"
        "testRejectMissingNestedPlugin"
        "testRejectMissingPlugins"
        "testRejectNestedUnknown"
        "testRejectNullConfig"
        "testRejectNullTrigger"
        "testRejectTimingModuleProperty"
        "testRejectTriggerModuleProperty"
        "testRejectUnknownKey"
      ];
      input = [
        "testAllDependenciesInspected"
        "testIndependentParentAndDependencyTiming"
        "testNestedDependency"
        "testPackageShorthand"
        "testRecursiveDefinitionRetained"
        "testRejectInvalidTiming"
        "testRejectMissingPlugin"
        "testRejectNonListDependencies"
        "testRejectNonListInput"
        "testShorthandHasNoTimingDefault"
      ];
      resolver = [
        "testConfigConflict"
        "testConflictNotHiddenByToolQuery"
        "testContextualPackage"
        "testCycleStartup"
        "testCycleTools"
        "testDefaultStartupTiming"
        "testDependencyOrder"
        "testDetailedSettings"
        "testDeterministicOrder"
        "testDoNotEvaluatePackagePluginDependencies"
        "testEmpty"
        "testFiniteCycle"
        "testIgnorePackagePluginDependencies"
        "testInvalidDependencyTools"
        "testInvalidRootTools"
        "testNestedAndShared"
        "testNestedConflict"
        "testNestedStringContextConflict"
        "testNoTriggerConcatenation"
        "testOptEvenAtStartup"
        "testPackageShorthand"
        "testPreservePackageBuildInputs"
        "testRepeatedDefinitions"
        "testRootAndRecursiveTools"
        "testRootMetadata"
        "testSameNamesDifferentPaths"
        "testSelfDependency"
        "testStartupClosure"
        "testStringContextConflict"
        "testTimingConflict"
      ];
      compiler = [
        "testAcceptOperatorPendingKeyMode"
        "testAfterConflict"
        "testAfterDefaultAndFalse"
        "testAfterOptIn"
        "testAfterRepeatedAndNested"
        "testDefaultStartupDetailedAndNested"
        "testDefaultStartupShorthand"
        "testDependencyStartupUnit"
        "testEmitLuaCallbacks"
        "testEmptyPlan"
        "testExplicitDeferredOverridesOmission"
        "testExplicitStartupOverridesOmission"
        "testGeneratedPlanInvariants"
        "testNormalizeCommandTrigger"
        "testNormalizeEventAliases"
        "testNormalizeEveryEventCase"
        "testNormalizeKeyTriggers"
        "testRejectEmptyCommand"
        "testRejectInvalidAfter"
        "testRejectInvalidConfig"
        "testRejectInvalidKeyMode"
        "testRejectInvalidLoad"
        "testRejectInvalidPreConfig"
        "testRejectInvalidStartupConfig"
        "testRejectRelativeRuntimePath"
        "testRejectUnknownEvent"
        "testRejectUnknownRootSettings"
        "testRejectUnknownSettings"
        "testTriggerlessDeferredPlan"
        "testUniquePluginNames"
      ];
    };
  };
}
