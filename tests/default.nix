{ lib }:
let
  suites = {
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
        "testNoInventedTiming"
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
        "testDependencyStartupUnit"
        "testEmitLuaCallbacks"
        "testEmptyPlan"
        "testNormalizeCommandTrigger"
        "testNormalizeKeyTriggers"
        "testRejectEmptyCommand"
        "testRejectInvalidConfig"
        "testRejectInvalidKeyMode"
        "testRejectMissingTiming"
        "testRejectRelativeRuntimePath"
        "testRejectUnknownRootSettings"
        "testRejectUnknownSettings"
        "testTriggerlessDeferredPlan"
        "testUniquePluginNames"
      ];
    };
  };
}
