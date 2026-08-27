## filegen\.generatedFiles

The list of generated files\.



*Type:*
list of string *(read only)*



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)



## filegen\.scripts\.activate



A script that applies the files configured with ` filegen.files `\.



*Type:*
path in the Nix store *(read only)*

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)



## filegen\.settings\.files



Declare file manipulations to perform in the project directory\.

This is intended to do things like create GitHub workflow files,
pre-commit hook configuration, or to generate or place other
miscellaneous configuration files used for development in the
repository\.

To generate the files, an “app” named ` filegen-activate ` is created,
which can be executed with ` nix run .#filegen-activate `\.

Note: This module does *not* attempt to protect against writes to or
reads from files outside of the repository\.

Trying to protect against this is considered somewhat pointless; At
the end of the day, you have to trust (or inspect) the flakes whose
code you execute anyway, as they can simply override what this module
does\. A future version might however still add checks simply to
prevent mistakes and anti-patterns\.



*Type:*
list of (submodule)



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)



## filegen\.settings\.files\.\*\.clobber



Whether to backup files that already exist\. If true or unset, the files
will just be deleted\.



*Type:*
null or boolean



*Default:*

```nix
null
```

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)



## filegen\.settings\.files\.\*\.permissions



The permissions of the created file\.

Only the execute bit will be preserved by git, so this should
practically always be “600” or “700”, but other values are
technically possible\.



*Type:*
string



*Default:*

```nix
"600"
```

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)



## filegen\.settings\.files\.\*\.source



The source of the file operation\.

This *can* be a nix store path, potentially created by interpolating a
variable\.



*Type:*
null or absolute path



*Default:*

```nix
null
```

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)



## filegen\.settings\.files\.\*\.target



The target of the file operation\.

To create a file in-repo, use ` . ` as the project root\.



*Type:*
relative path

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)



## filegen\.settings\.files\.\*\.type



The type of operation to perform on the given file\.

Normally, this should be set to ` copy `\.



*Type:*
value “copy” (singular enum)

*Declared by:*
 - [/nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen\.nix](file:///nix/store/zzd71snai9np0k2yknk2avgi1wd944i0-source/nix/modules/filegen.nix)


