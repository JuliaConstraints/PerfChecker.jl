# Julia API

This page indexes the documented public API exported by `PerfChecker`. Start
with `SoftwareSuite`, `FeatureSpec`, `plan_suite`, and `run_suite` for new code;
the original `@check`/`PerfConfig` surface remains available for compatibility.
Some extension entry points gain methods only after their optional package is
loaded. See [extensions and providers](extensions.md) for activation rules.

## Index

```@index
Modules = [PerfChecker]
```

## Public docstrings

```@autodocs
Modules = [PerfChecker]
Public = true
Order = [:module, :constant, :type, :macro, :function]
```
