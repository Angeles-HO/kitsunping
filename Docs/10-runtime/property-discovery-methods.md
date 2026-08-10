# Property discovery methods (beyond getprop/build.prop)

Last update: 2026-07-14

## Why this exists

`getprop` (without args) and `build.prop` only expose properties that are already
set at runtime or baked in known prop files.

Many real properties are:

- read with defaults but never set,
- set later by init triggers/HAL/vendor daemons,
- only visible as string constants in native binaries or framework code.

## Tool

Use [tools/property_inventory.sh](../../tools/property_inventory.sh).

### 1) Static inventory (recommended first pass)

```sh
sh tools/property_inventory.sh static
```

This collects property keys from:

- `plat/vendor/odm/product_property_contexts`
- `init/*.rc` (`setprop`, `resetprop`, `on property:*` triggers)
- known `*.prop` files

Optional binary-string scan (heavier):

```sh
sh tools/property_inventory.sh static --with-binaries
```

### 2) Filtered network candidates (recommended for new research)

```sh
sh tools/property_inventory.sh candidates
```

This mode does not read `build.prop` as a candidate source. It derives
network-related property names only from property contexts and init triggers,
optionally adding binary strings with `--with-binaries`. It excludes keys that
are already visible through `getprop`, module-owned `kitsunping.*` keys,
read-only `ro.*` keys, and generic runtime namespaces.

The generated TSV contains `property` and `static_sources`. It is a research
queue, not an instruction to write a property. Each row still needs an owner,
reader, OEM/API gate, observable effect and rollback before it can become a
Kitsunping experiment.

### 3) Runtime snapshot

```sh
sh tools/property_inventory.sh snapshot /sdcard/props.before.txt
```

### 4) Dynamic diff around a feature toggle

```sh
# before
sh tools/property_inventory.sh snapshot /sdcard/props.before.txt

# enable / trigger feature
setprop persist.kitsunping.some_toggle 1

# after
sh tools/property_inventory.sh snapshot /sdcard/props.after.txt

# diff
sh tools/property_inventory.sh diff /sdcard/props.before.txt /sdcard/props.after.txt
```

This reveals added/removed/changed keys even when they are not in `build.prop`.

## Practical workflow for Kitsunping investigations

1. Run `candidates` to create an evidence-backed queue beyond `getprop` and
	`build.prop`.
2. Inspect its source files and follow the property consumer before proposing a
	test.
3. Capture `snapshot` before action.
4. Trigger app/module/router scenario.
5. Capture `snapshot` after action.
6. Run `diff` and map resulting keys to runtime scripts.

## Notes

- Binary scan can be expensive; run only when needed.
- For rooted diagnostics, combine this with process-level tracing when available.
- Keep findings in runtime docs, not in release metadata.
