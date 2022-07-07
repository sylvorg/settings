{ description = "Our tools and settings!";
    nixConfig = {
        # Adapted From: https://github.com/divnix/digga/blob/main/examples/devos/flake.nix#L4
        # extra-substituters = "https://cache.nixos.org/ https://nix-community.cachix.org/";
        trusted-substituters = "https://cache.nixos.org/";
        # extra-trusted-public-keys = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
        trusted-public-keys = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
        # keep-derivations = true;
        # keep-outputs = true;
        extra-experimental-features = "nix-command flakes";
        # flake-registry = https://raw.githubusercontent.com/sylvorg/settings/main/flake-registry.json;
        # allow-unsafe-native-code-during-evaluation = true;
        # min-free = 262144000;
        # max-free = 1073741824;
    };
    inputs = {
        emacs.url = github:nix-community/emacs-overlay;
        nix.url = github:nixos/nix;
        nur.url = github:nix-community/nur;
        node2nix = {
            url = github:svanderburg/node2nix;
            flake = false;
        };

        flake-utils.url = github:numtide/flake-utils;
        flake-compat = {
            url = github:edolstra/flake-compat;
            flake = false;
        };

        nixos-21-11-small.url = github:NixOS/nixpkgs/nixos-21.11-small;
        nixos-21-11.url = github:NixOS/nixpkgs/nixos-21.11;
        nixos-22-05-small.url = github:NixOS/nixpkgs/nixos-22.05-small;
        nixos-22-05.url = github:NixOS/nixpkgs/nixos-22.05;
        nixos-master.url = github:NixOS/nixpkgs/master;
        nixos-unstable-small.url = github:NixOS/nixpkgs/nixos-unstable-small;
        nixos-unstable.url = github:NixOS/nixpkgs/nixos-unstable;
        nixpkgs.url = github:NixOS/nixpkgs/nixos-22.05;
    };
    outputs = inputs@{ self, flake-utils, ... }: with builtins; with flake-utils.lib; let
        channel = nixos-22-05;
        registry = fromJSON ''
{
  "flakes": [
    {
      "from": {
        "id": "shadowrylander",
        "type": "indirect"
      },
      "to": {
        "owner": "shadowrylander",
        "repo": "shadowrylander",
        "type": "github"
      }
    },
    {
      "from": {
        "id": "settings",
        "type": "indirect"
      },
      "to": {
        "owner": "sylvorg",
        "repo": "settings",
        "type": "github"
      }
    }
  ],
  "version": 2
}
        '';
        patch = {
            nixpkgs = let
                patches' = [ patches.bcachefs-module ];
            in {
                default = src: config: (import src config).applyPatches {
                    name = "defaultPatches";
                    inherit src;
                    patches = patches';
                };
                extras = src: config: patches: (import src config).applyPatches { name = "extraPatches"; inherit src patches; };
                both = src: config: patches: (import src config).applyPatches {
                    name = "bothPatches";
                    inherit src;
                    patches = patches' ++ patches;
                };
            };
            pkgs = {
                default = src: config: import (patch.nixpkgs.default src config) config;
                extras = src: config: patches: import (patch.nixpkgs.extras src config patches) config;
            };
        };
        lib = inputs.nixpkgs.lib.extend (final: prev: { j = with final; makeExtensible (self: rec {
            genAttrNames = values: f: listToAttrs (map (v: nameValuePair (f v) v) values);
            mapAttrNames = f: mapAttrs' (n: v: nameValuePair (f n v) v);
            mif = {
                list = optionals;
                list' = optional;
                set = optionalAttrs;
                num = condition: value: if condition then value else 0;
                null = condition: value: if condition then value else null;
                str = optionalString;
            };
            foldToSet = list: foldr (new: old: new // old) {} (filter isAttrs (flatten list));
            foldToSet' = list: foldr (new: old: recursiveUpdate new old) {} (filter isAttrs (flatten list));
            readDirExists = dir: mif.set (pathExists dir) (readDir dir);
            dirCon = let
                ord = func: dir: filterAttrs func (if (isAttrs dir) then dir else (readDirExists dir));
            in rec {
                attrs = {
                    dirs = ord (n: v: v == "directory");
                    others = ord (n: v: v != "directory");
                    files = ord (n: v: v == "regular");
                    sym = ord (n: v: v == "symlink");
                    unknown = ord (n: v: v == "unknown");
                };
                dirs = dir: attrNames (attrs.dirs dir);
                others = dir: attrNames (attrs.others dir);
                files = dir: attrNames (attrs.files dir);
                sym = dir: attrNames (attrs.sym dir);
                unknown = dir: attrNames (attrs.unknown dir);
            };
            has = {
                prefix = string: any (flip hasPrefix string);
                suffix = string: any (flip hasSuffix string);
                infix = string: any (flip hasInfix string);
            };
            filters = {
                has = {
                    attrs = list: attrs: let
                        l = unique (flatten list);
                    in foldToSet [
                        (filterAttrs (n: v: elem n l) attrs)
                        (genAttrNames (filter isDerivation l) (drv: drv.pname or drv.name))
                    ];
                    list = list: attrs: attrValues (filters.has.attrs list attrs);

                    # Roger, roger!
                    attr-attr = attrs: filterAttrs (n: v: elem n (attrNames attrs));

                };
                keep = {
                    prefix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: has.prefix n (toList keeping)) attrs);
                    suffix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: has.suffix n (toList keeping)) attrs);
                    infix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: has.infix n (toList keeping)) attrs);
                    elem = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: elem n (toList keeping)) attrs);
                    inherit (dirCon.attrs) dirs others files sym unknown;
                    readDir = {
                        dirs = {
                            prefix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "directory") then (has.prefix n (toList keeping)) else true) attrs);
                            suffix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "directory") then (has.suffix n (toList keeping)) else true) attrs);
                            infix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "directory") then (has.infix n (toList keeping)) else true) attrs);
                            elem = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "directory") then (elem n (toList keeping)) else true) attrs);
                        };
                        others = {
                            prefix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v != "directory") then (has.prefix n (toList keeping)) else true) attrs);
                            suffix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v != "directory") then (has.suffix n (toList keeping)) else true) attrs);
                            infix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v != "directory") then (has.infix n (toList keeping)) else true) attrs);
                            elem = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v != "directory") then (elem n (toList keeping)) else true) attrs);
                        };
                        files = {
                            prefix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "regular") then (has.prefix n (toList keeping)) else true) attrs);
                            suffix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "regular") then (has.suffix n (toList keeping)) else true) attrs);
                            infix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "regular") then (has.infix n (toList keeping)) else true) attrs);
                            elem = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "regular") then (elem n (toList keeping)) else true) attrs);
                        };
                        sym = {
                            prefix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "symlink") then (has.prefix n (toList keeping)) else true) attrs);
                            suffix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "symlink") then (has.suffix n (toList keeping)) else true) attrs);
                            infix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "symlink") then (has.infix n (toList keeping)) else true) attrs);
                            elem = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "symlink") then (elem n (toList keeping)) else true) attrs);
                        };
                        unknown = {
                            prefix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "unknown") then (has.prefix n (toList keeping)) else true) attrs);
                            suffix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "unknown") then (has.suffix n (toList keeping)) else true) attrs);
                            infix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "unknown") then (has.infix n (toList keeping)) else true) attrs);
                            elem = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if (v == "unknown") then (elem n (toList keeping)) else true) attrs);
                        };
                        static = {
                            prefix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (has.prefix n (toList keeping)) else true) attrs);
                            suffix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (has.suffix n (toList keeping)) else true) attrs);
                            infix = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (has.infix n (toList keeping)) else true) attrs);
                            elem = keeping: attrs: if ((keeping == []) || (keeping == "")) then attrs else (filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (elem n (toList keeping)) else true) attrs);
                        };
                    };
                };
                remove = {
                    prefix = ignores: filterAttrs (n: v: ! (has.prefix n (toList ignores)));
                    suffix = ignores: filterAttrs (n: v: ! (has.suffix n (toList ignores)));
                    infix = ignores: filterAttrs (n: v: ! (has.infix n (toList ignores)));
                    elem = ignores: filterAttrs (n: v: ! (elem n (toList ignores)));
                    dirs = dirCon.attrs.others;
                    files = filterAttrs (n: v: v != "regular");
                    others = dirCon.attrs.dirs;
                    sym = filterAttrs (n: v: v != "symlink");
                    unknown = filterAttrs (n: v: v != "unknown");
                    readDir = {
                        dirs = {
                            prefix = ignores: filterAttrs (n: v: (! (has.prefix n (toList ignores))) && (v == "directory"));
                            suffix = ignores: filterAttrs (n: v: (! (has.suffix n (toList ignores))) && (v == "directory"));
                            infix = ignores: filterAttrs (n: v: (! (has.infix n (toList ignores))) && (v == "directory"));
                            elem = ignores: filterAttrs (n: v: (! (elem n (toList ignores))) && (v == "directory"));
                        };
                        others = {
                            prefix = ignores: filterAttrs (n: v: if (v != "directory") then (! (has.prefix n (toList ignores))) else true);
                            suffix = ignores: filterAttrs (n: v: if (v != "directory") then (! (has.suffix n (toList ignores))) else true);
                            infix = ignores: filterAttrs (n: v: if (v != "directory") then (! (has.infix n (toList ignores))) else true);
                            elem = ignores: filterAttrs (n: v: if (v != "directory") then (! (elem n (toList ignores))) else true);
                        };
                        files = {
                            prefix = ignores: filterAttrs (n: v: if (v == "regular") then (! (has.prefix n (toList ignores))) else true);
                            suffix = ignores: filterAttrs (n: v: if (v == "regular") then (! (has.suffix n (toList ignores))) else true);
                            infix = ignores: filterAttrs (n: v: if (v == "regular") then (! (has.infix n (toList ignores))) else true);
                            elem = ignores: filterAttrs (n: v: if (v == "regular") then (! (elem n (toList ignores))) else true);
                        };
                        sym = {
                            prefix = ignores: filterAttrs (n: v: if (v == "symlink") then (! (has.prefix n (toList ignores))) else true);
                            suffix = ignores: filterAttrs (n: v: if (v == "symlink") then (! (has.suffix n (toList ignores))) else true);
                            infix = ignores: filterAttrs (n: v: if (v == "symlink") then (! (has.infix n (toList ignores))) else true);
                            elem = ignores: filterAttrs (n: v: if (v == "symlink") then (! (elem n (toList ignores))) else true);
                        };
                        unknown = {
                            prefix = ignores: filterAttrs (n: v: if (v == "unknown") then (! (has.prefix n (toList ignores))) else true);
                            suffix = ignores: filterAttrs (n: v: if (v == "unknown") then (! (has.suffix n (toList ignores))) else true);
                            infix = ignores: filterAttrs (n: v: if (v == "unknown") then (! (has.infix n (toList ignores))) else true);
                            elem = ignores: filterAttrs (n: v: if (v == "unknown") then (! (elem n (toList ignores))) else true);
                        };
                        static = {
                            prefix = keeping: filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (! (has.prefix n (toList keeping))) else true);
                            suffix = keeping: filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (! (has.suffix n (toList keeping))) else true);
                            infix = keeping: filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (! (has.infix n (toList keeping))) else true);
                            elem = keeping: filterAttrs (n: v: if ((v == "regular") || (v == "unknown")) then (! (elem n (toList keeping))) else true);
                        };
                    };
                };
            };
            imports = rec {
                name = {
                    file,
                    suffix ? ".nix",
                }: let
                    base-file = baseNameOf (toString file);
                in if (isInt suffix) then (let
                    hidden = hasPrefix "." base-file;
                    split-file = remove "" (splitString "." base-file);
                in if (hidden && ((length split-file) == 1)) then base-file
                else concatStringsSep "." (take ((length split-file) - suffix) split-file)) else (removeSuffix suffix base-file);
                list = args@{
                    dir,
                    idir ? dir,
                    ignores ? {},
                    iter ? 0,
                    keep ? false,
                    keeping ? {},
                    local ? false,
                    file ? { prefix = { pre = ""; post = ""; }; suffix = ""; },
                    recursive ? false,
                    root ? false,
                    names ? false,
                    suffix ? ".nix",
                }: let
                    func = dir: let
                        stringDir = toString dir;
                        stringyDir = toString idir;
                        fk = filters.keep;
                        fr = filters.remove;
                        pre-orders = flatten [
                            (optional (keeping.files or false) fk.files)
                            (optional (keeping.unknown or false) fk.unknown)
                            (fk.prefix (keeping.prefix or []))
                            (fk.infix (keeping.infix or []))
                            (fk.readDir.files.suffix (keeping.suffix or []))
                            (fk.readDir.files.elem (keeping.elem or []))
                            (fk.readDir.unknown.suffix (keeping.suffix or []))
                            (fk.readDir.unknown.elem (keeping.elem or []))
                            (fk.readDir.static.suffix (keeping.suffix or []))
                            (fk.readDir.static.elem (keeping.elem or []))
                            (optional (ignores.files or false) fr.files)
                            (optional (ignores.unknown or false) fr.unknown)
                            (fr.prefix (ignores.prefix or []))
                            (fr.infix (ignores.infix or []))
                            (fr.readDir.files.suffix (ignores.suffix or []))
                            (fr.readDir.files.elem (ignores.elem or []))
                            (fr.readDir.unknown.suffix (ignores.suffix or []))
                            (fr.readDir.unknown.elem (ignores.elem or []))
                            (fr.readDir.static.suffix (ignores.suffix or []))
                            (fr.readDir.static.elem (ignores.elem or []))
                        ];
                        orders = flatten [
                            (optional (keeping.dirs or false) fk.dirs)
                            (optional (keeping.others or false) fk.others)
                            (optional (keeping.sym or false) fk.sym)
                            (fk.suffix (keeping.suffix or []))
                            (fk.elem (keeping.elem or []))
                            (optional (ignores.dirs or false) fr.dirs)
                            (optional (ignores.others or false) fr.others)
                            (optional (ignores.sym or false) fr.sym)
                            (fr.suffix (ignores.suffix or []))
                            (fr.elem (ignores.elem or []))
                        ];
                        pipe-list = flatten [
                            (mapAttrNames (n: v: pipe "${removePrefix stringyDir stringDir}/${n}" [
                                (splitString "/")
                                (remove "")
                                (concatStringsSep "/")
                            ]))
                            pre-orders
                        ];
                        items = let
                            filtered-others = pipe (dirCon.attrs.others dir) pipe-list;
                            filtered-dirs = pipe (dirCon.attrs.dirs dir) (flatten [
                                pipe-list
                                (optionals recursive (mapAttrsToList (n: v: list (args // { dir = "${stringyDir}/${n}"; inherit idir; iter = iter + 1; }))))
                            ]);
                        in foldToSet [ filtered-others filtered-dirs ];
                        process = s: pipe s (flatten [
                            pipe-list
                            orders
                            (if names then (mapAttrNames (file: v: name { inherit suffix file; })) else [
                                (mapAttrNames (n: v: (file.prefix.pre or "") + n))
                                (mapAttrNames (n: v: if keep then n
                                                    else if local then "./${n}"
                                                    else if root then "/${n}"
                                                    else "${stringDir}/${n}"))
                                (mapAttrNames (n: v: (file.prefix.post or "") + n + (file.suffix or "")))
                            ])
                            attrNames
                        ]);
                    in if (iter == 0) then (process items) else items;
                in flatten (map func (toList dir));
                set = args@{
                    call ? null,
                    dir,
                    extrargs ? {},
                    suffix ? ".nix",
                    ...
                }: listToAttrs (map (file: nameValuePair
                    (name { inherit file suffix; })
                    (if (call != null) then (call.callPackage file extrargs)
                    else if (extrargs == {}) then (import file)
                    else (import file extrargs))
                ) (list (filterAttrs (n: v: ! (elem n [ "call" "extrargs" ])) args)));
                overlaySet = args@{
                    call ? null,
                    dir,
                    extrargs ? {},
                    func ? null,
                    suffix ? ".nix",
                    ...
                }: listToAttrs (map (file: let
                    filename = name { inherit file suffix; };
                in nameValuePair
                    filename
                    (if (func != null) then (func file)
                    else if ((isInt call) && (call == 1)) then (final: prev: { "${filename}" = final.callPackage file extrargs; })
                    else if ((isInt call) && (call == 0)) then (final: prev: { "${filename}" = prev.callPackage file extrargs; })
                    else if (call != null) then (final: prev: { "${filename}" = call.callPackage file extrargs; })
                    else if (extrargs == {}) then (import file)
                    else (import file extrargs))
                ) (list (filterAttrs (n: v: ! (elem n [ "call" "extrargs" "func" ])) (recursiveUpdate args { ignores.dirs = true; }))));
            };
            update = {
                python = rec {
                    python = rec {
                        base = pv: attrs: prev: { "${pv}" = prev.${pv}.override (super: {
                            packageOverrides = lib.composeExtensions (super.packageOverrides or (_: _: {})) (new: old: attrs);
                        }); };
                        two = base attrs.versions.python.two;
                        three = base attrs.versions.python.three;
                    };
                    callPython = rec {
                        base = pv: name: pkg: final: python.base pv { "${name}" = final.${pv}.pkgs.callPackage pkg {}; };
                        two = base attrs.versions.python.two;
                        three = base attrs.versions.python.three;
                    };
                    callPython' = rec {
                        base = pv: file: final: python.base pv { "${imports.name { inherit file; }}" = final.${pv}.pkgs.callPackage file {}; };
                        two = base attrs.versions.python.two;
                        three = base attrs.versions.python.three;
                    };
                    package = rec {
                        base = pv: pkg: func: prev: python.base pv { "${pkg}" = prev.${pv}.pkgs.${pkg}.overridePythonAttrs func; } prev;
                        two = base attrs.versions.python.two;
                        three = base attrs.versions.python.three;
                    };
                    packages = rec {
                        base = pv: dir: final: python.base pv (imports.set { call = final.${pv}.pkgs; inherit dir; ignores.elem = dirCon.dirs dir; });
                        two = base attrs.versions.python.two;
                        three = base attrs.versions.python.three;
                    };
                };
                node = rec {
                    default = overlay: final: prev: {
                        nodePackages = fix (extends (final.callPackage overlay {}) (new: prev.nodePackages));
                    };
                };
            };

            baseVersion = head (splitString "p" (concatStringsSep "." (take 2 (splitString "." version))));
            zipToSet = names: values: listToAttrs (
                map (nv: nameValuePair nv.fst nv.snd) (let hasAttrs = any isAttrs values; in zipLists (
                    if hasAttrs then names else (sort lessThan names)
                ) (
                    if hasAttrs then values else (sort lessThan values)
                ))
            );
            toCapital = string: concatImapStrings (
                i: v: if (i == 1) then (toUpper v) else v
            ) (stringToCharacters string);

            # foldr func end list
            sequence = foldr deepSeq;

            attrs = rec {
                configs = {
                    nixpkgs = {
                        allowUnfree = true;
                        allowBroken = true;
                        allowUnsupportedSystem = true;
                        # preBuild = ''
                        #     makeFlagsArray+=(CFLAGS="-w")
                        #     buildFlagsArray+=(CC=cc)
                        # '';
                        permittedInsecurePackages = [
                            "python2.7-cryptography-2.9.2"
                        ];
                    };
                };
                platforms = {
                    arm = [ "aarch64-linux" "armv7l-linux" "armv6l-linux" ];
                    imd = [ "i686-linux" "x86_64-linux" ];
                };
                versions = {
                    python = rec {
                        two' = "7";
                        three' = "10";
                        two = "python2${two'}";
                        three = "python3${three'}";
                    };
                };
            };

            inherit patch;
        }); });
        callPackages = with lib; {
            settings = { stdenv }: stdenv.mkDerivation rec {
                pname = "settings";
                version = "1.0.0.0";
                src = ./.;
                phases = [ "installPhase" ];
                installPhase = ''
                    mkdir --parents $out
                    cp -r $src/bin $out/bin
                    chmod +x $out/bin/*
                '';
                meta.mainprogram = "org-tangle";
            };
            pacapt = { stdenv, fetchFromGitHub }: let
                owner = "icy";
            in stdenv.mkDerivation rec {
                pname = "pacapt";
                version = "3.0.7";
                src = fetchFromGitHub {
                    inherit owner;
                    repo = pname;
                    rev = "v${version}";
                    sha256 = "07zjdhn21rnacv2i59h91q4ykbqvsab4pmgqv8c952fzi3m5gjk4";
                };
                installPhase = ''
                    mkdir --parents $out/bin
                    cp $src/${pname} $out/bin/
                    chmod 755 $out/bin/*
                '';
                meta = {
                    description = "An ArchLinux's pacman-like shell wrapper for many package managers. 56KB and run anywhere.";
                    homepage = "https://github.com/${owner}/${pname}";
                };
            };
            flk = { stdenv, fetchgit }: let
                owner = "chr15m";
            in stdenv.mkDerivation rec {
                pname = "flk";
                version = "1.0.0.0";
                src = fetchgit {
                    url = "https://github.com/${owner}/${pname}.git";
                    rev = "46a88bdb461dda336d5aca851c16d938e05304dc";
                    sha256 = "sha256-NAhWe0O1K3LOdIwYNOHfkBzkGm+h0wckpsCuY/lY/+8=";
                    deepClone = true;
                };
                installPhase = ''
                    mkdir --parents $out/bin
                    cp ./docs/${pname} $out/bin/
                '';
                meta = {
                    description = "A LISP that runs wherever Bash is";
                    homepage = "https://github.com/${owner}/${pname}";
                    license = licenses.mpl20;
                };
            };
            mdsh = { stdenv, fetchFromGitHub }: let
                owner = "bashup";
            in stdenv.mkDerivation rec {
                pname = "mdsh";
                version = "1.0.0.0";
                src = fetchFromGitHub {
                    inherit owner;
                    repo = pname;
                    rev = "7e7af618a341eebd50e7825b062bc192079ad5fc";
                    sha256 = "1wg5iy1va2fl843rish2q1kif818cz8mnhwmg88ir5p364fc2kcp";
                };
                installPhase = ''
                    mkdir --parents $out/bin
                    cp $src/bin/${pname} $out/bin/
                '';
                meta = {
                    description = "Multi-lingual, Markdown-based Literate Programming... in run-anywhere bash";
                    homepage = "https://github.com/${owner}/${pname}";
                    license = licenses.mit;
                };
            };
            caddy = { fetchFromGitHub, buildGoModule }: let
                imports = concatMapStrings (pkg: "\t\t\t_ \"${pkg}\"\n") [
                    "github.com/mholt/caddy-l4@latest"
                    "github.com/abiosoft/caddy-yaml@latest"
                    "github.com/caddy-dns/cloudflare@latest"
                ];
                main = ''
                    package main

                    import (
                        caddycmd "github.com/caddyserver/caddy/v2/cmd"
                        _ "github.com/caddyserver/caddy/v2/modules/standard"
                        ${imports}
                    )

                    func main() {
                        caddycmd.Main()
                    }
                '';
            in buildGoModule rec {
                pname = "caddy";
                version = "2.5.1";
                proxyVendor = true;
                subPackages = [ "cmd/caddy" ];
                src = fetchFromGitHub {
                    owner = "caddyserver";
                    repo = pname;
                    rev = "v${version}";
                    sha256 = "1nlphjg5wh5drpwkm4cczrkxdzbv72ll7hp5x7z6ww8pzz3q10b3";
                };
                vendorSha256 = "sha256-xu3klc9yb4Ws8fvXRV286IDhi/zQVN1PKCiFKb8VJBo=";
                overrideModAttrs = (_: {
                    preBuild    = "echo '${main}' > cmd/caddy/main.go";
                    postInstall = "cp go.sum go.mod $out/";
                });
                postPatch = "echo '${main}' > cmd/caddy/main.go";
                postConfigure = ''
                    cp vendor/go.sum ./
                    cp vendor/go.mod ./
                '';
                meta = {
                    homepage = https://caddyserver.com;
                    description = "Fast, cross-platform HTTP/2 web server with automatic HTTPS";
                    license = licenses.asl20;
                    maintainers = with maintainers; [ Br1ght0ne ];
                };
            };
            guix = { stdenv, fetchurl }: stdenv.mkDerivation rec {
                pname = "guix";
                version = "1.0.0";
                src = fetchurl {
                url = "https://ftp.gnu.org/gnu/guix/guix-binary-${version}.${stdenv.targetPlatform.system}.tar.xz";
                sha256 = {
                    "x86_64-linux" = "11y9nnicd3ah8dhi51mfrjmi8ahxgvx1mhpjvsvdzaz07iq56333";
                    "i686-linux" = "14qkz12nsw0cm673jqx0q6ls4m2bsig022iqr0rblpfrgzx20f0i";
                    "aarch64-linux" = "0qzlpvdkiwz4w08xvwlqdhz35mjfmf1v3q8mv7fy09bk0y3cwzqs";
                    }."${stdenv.targetPlatform.system}";
                };
                sourceRoot = ".";
                outputs = [ "out" "store" "var" ];
                phases = [ "unpackPhase" "installPhase" ];
                installPhase = ''
                    # copy the /gnu/store content
                    mkdir -p $store
                    cp -r gnu $store

                    # copy /var content
                    mkdir -p $var
                    cp -r var $var

                    # link guix binaries
                    mkdir -p $out/bin
                    ln -s /var/guix/profiles/per-user/root/current-guix/bin/guix $out/bin/guix
                    ln -s /var/guix/profiles/per-user/root/current-guix/bin/guix-daemon $out/bin/guix-daemon
                '';
                meta = {
                    description = "The GNU Guix package manager";
                    homepage = https://www.gnu.org/software/guix/;
                    license = licenses.gpl3Plus;
                    maintainers = [ maintainers.johnazoidberg ];
                    platforms = [ "aarch64-linux" "i686-linux" "x86_64-linux" ];
                };
            };
            poetry2setup = { lib, Python, fetchFromGitHub, gawk }: Python.pkgs.buildPythonApplication rec {
                pname = "poetry2setup";
                version = "1.0.0";
                format = "pyproject";

                src = fetchFromGitHub {
                    owner = "abersheeran";
                    repo = pname;
                    rev = "6d3345f488fda4d0f6eed1bd3438ea6207e55e3a";
                    sha256 = "07z776ikj37whhx7pw1f3pwp25w04aw22vwipjjmvi8c642qxni4";
                };

                propagatedBuildInputs = with Python.pkgs; [ poetry-core ];

                buildInputs = with Python.pkgs; [ poetry-core ];

                installPhase = ''
                    mkdir --parents $out/bin
                    cp $src/${pname}.py $out/bin/${pname}
                    chmod +x $out/bin/${pname}
                    ${gawk}/bin/awk -i inplace 'BEGINFILE{print "#!/usr/bin/env python3"}{print}' $out/bin/${pname}
                '';

                postFixup = "wrapProgram $out/bin/${pname} $makeWrapperArgs";

                makeWrapperArgs = [ "--prefix PYTHONPATH : ${placeholder "out"}/lib/${Python.pkgs.python.libPrefix}/site-packages" ];

                meta = {
                    description = "Convert python-poetry(pyproject.toml) to setup.py.";
                    homepage = "https://github.com/abersheeran/${pname}";
                    license = licenses.mit;
                };
            };
            nodejs = {
                uglifycss =  {nodeEnv, fetchurl, fetchgit, nix-gitignore, stdenv, lib, globalBuildInputs ? []}: let
                    sources = {};
                in {
                    uglifycss = nodeEnv.buildNodePackage {
                        name = "uglifycss";
                        packageName = "uglifycss";
                        version = "0.0.29";
                        src = fetchurl {
                            url = "https://registry.npmjs.org/uglifycss/-/uglifycss-0.0.29.tgz";
                            sha512 = "J2SQ2QLjiknNGbNdScaNZsXgmMGI0kYNrXaDlr4obnPW9ni1jljb1NeEVWAiTgZ8z+EBWP2ozfT9vpy03rjlMQ==";
                        };
                        buildInputs = globalBuildInputs;
                        meta = {
                            description = "Port of YUI CSS Compressor to NodeJS";
                            homepage = "https://github.com/fmarcia/uglifycss";
                            license = "MIT";
                        };
                        production = true;
                        bypassCache = true;
                        reconstructLock = true;
                    };
                };
            };
            python = {
                two = {
                };
                three = {
                    autoslot = { lib, buildPythonPackage, fetchFromGitHub, pytestCheckHook, flit }: let
                        owner = "cjrh";
                    in buildPythonPackage rec {
                        pname = "autoslot";
                        version = "2021.10.1";
                        format = "pyproject";
                        src = fetchFromGitHub {
                            inherit owner;
                            repo = pname;
                            rev = "a36ea378136bc7dfdc11f3f950186f6ed8bee8c5";
                            sha256 = "1dds9dwf5bqxi84s1fzcdykiqgcc1iq3rh6p76wjz6h7cb451h08";
                        };
                        buildInputs = [ flit ];
                        nativeBuildInputs = buildInputs;
                        checkInputs = [ pytestCheckHook ];
                        pythonImportsCheck = [ pname ];
                        meta = {
                            description = "Automatic __slots__ for your Python classes";
                            homepage = "https://github.com/${owner}/${pname}";
                            license = lib.licenses.asl20;
                        };
                    };
                    magicattr = { lib, buildPythonPackage, fetchFromGitHub, pytestCheckHook, flit }: let
                        owner = "frmdstryr";
                    in buildPythonPackage rec {
                        pname = "magicattr";
                        version = "0.1.6";
                        src = fetchFromGitHub {
                            inherit owner;
                            repo = pname;
                            rev = "15ae93def3693661066624c9d760b26f6e205199";
                            sha256 = "1pq1xrlaadkdic9xlig8rv97zkymqgbikparfrdpdfifj19md6ql";
                        };
                        doCheck = false;
                        pythonImportsCheck = [ pname ];
                        meta = {
                            description = "A getattr and setattr that works on nested objects, lists, dicts, and any combination thereof without resorting to eval";
                            homepage = "https://github.com/${owner}/${pname}";
                            license = lib.licenses.mit;
                        };
                    };
                    backtrace = { lib, buildPythonPackage, fetchFromGitHub, pytestCheckHook, colorama }: let
                        owner = "nir0s";
                    in buildPythonPackage rec {
                        pname = "backtrace";
                        version = "0.2.1";
                        src = fetchFromGitHub {
                            inherit owner;
                            repo = pname;
                            rev = "a1f75c956f669a6175088693802d5392e6bd7e51";
                            sha256 = "1i3xj04zxz9vi57gbkmnnyh9cypf3bm966ic685s162p1xhnz2qp";
                        };
                        propagatedBuildInputs = [ colorama ];
                        checkInputs = [ pytestCheckHook ];
                        pythonImportsCheck = [ pname ];
                        meta = {
                            description = "Makes Python tracebacks human friendly";
                            homepage = "https://github.com/${owner}/${pname}";
                            license = lib.licenses.asl20;
                        };
                    };
                };
                xonsh = {
                    xontrib-readable-traceback = { lib, buildPythonPackage, fetchPypi, colorama, backtrace }: buildPythonPackage rec {
                        pname = "xontrib-readable-traceback";
                        version = "0.3.2";
                        src = fetchPypi {
                            inherit pname version;
                            sha256 = "sha256-1D/uyiA3A1dn9IPakjighckZT5Iy2WOMroBkLMp/FZM=";
                        };
                        propagatedBuildInputs = [ colorama backtrace ];
                        meta = {
                            description = "xonsh readable traceback";
                            homepage = "https://github.com/vaaaaanquish/${pname}";
                            license = lib.licenses.mit;
                        };
                    };
                    xonsh-autoxsh = { lib, buildPythonPackage, fetchPypi }: buildPythonPackage rec {
                        pname = "xonsh-autoxsh";
                        version = "0.3";
                        src = fetchPypi {
                            inherit pname version;
                            sha256 = "sha256-qwXbNbQ5mAwkZ4N+htv0Juw2a3NF6pv0XpolLIQfIe4=";
                        };
                        meta = {
                            description = "Automatically execute scripts for directories in Xonsh Shell.";
                            homepage = "https://github.com/Granitosaurus/${pname}";
                            license = lib.licenses.mit;
                        };
                    };
                    xonsh-direnv = { lib, buildPythonPackage, fetchPypi }: buildPythonPackage rec {
                        pname = "xonsh-direnv";
                        version = "1.5.0";
                        src = fetchPypi {
                            inherit pname version;
                            sha256 = "sha256-OLjtGD2lX4Yf3aHrxCWmAbSPZnf8OuVrBu0VFbsna1Y=";
                        };
                        meta = {
                            description = "xonsh extension for using direnv";
                            homepage = "https://github.com/Granitosaurus/${pname}";
                            license = lib.licenses.mit;
                        };
                    };
                    xontrib-pipeliner = { lib, buildPythonPackage, fetchPypi, six }: buildPythonPackage rec {
                        pname = "xontrib-pipeliner";
                        version = "0.3.4";
                        src = fetchPypi {
                            inherit pname version;
                            sha256 = "sha256-f8tUjPEQYbycq1b3bhXwPU2YF9fkp1URqDDLH2CeNpo=";
                        };
                        propagatedBuildInputs = [ six ];
                        postPatch = ''
                            substituteInPlace setup.py --replace "'xonsh', " ""
                        '';
                        meta = {
                            description = "Let your pipe lines flow thru the Python code in xonsh.";
                            homepage = "https://github.com/anki-code/${pname}";
                            license = lib.licenses.mit;
                        };
                    };
                    xontrib-sh = { lib, buildPythonPackage, fetchPypi }: buildPythonPackage rec {
                        pname = "xontrib-sh";
                        version = "0.3.0";
                        src = fetchPypi {
                            inherit pname version;
                            sha256 = "sha256-eV++ZuopnAzNXRuafXXZM7tmcay1NLBIB/U+SVrQV+U=";
                        };
                        meta = {
                            description = "Paste and run commands from bash, zsh, fish, tcsh in xonsh shell.";
                            homepage = "https://github.com/anki-code/${pname}";
                            license = lib.licenses.mit;
                        };
                    };
                };
            };
        };
        patches = {
            bcachefs-module = toFile "bcachefs-module.patch" ''
diff --git a/nixos/modules/tasks/filesystems/bcachefs.nix b/nixos/modules/tasks/filesystems/bcachefs.nix
index 5fda24adb97..897ddf03927 100644
--- a/nixos/modules/tasks/filesystems/bcachefs.nix
+++ b/nixos/modules/tasks/filesystems/bcachefs.nix
@@ -45,7 +45,7 @@ in
       system.fsPackages = [ pkgs.bcachefs-tools ];
 
       # use kernel package with bcachefs support until it's in mainline
-      boot.kernelPackages = pkgs.linuxPackages_testing_bcachefs;
+      # boot.kernelPackages = pkgs.linuxPackages_testing_bcachefs;
     }
 
     (mkIf ((elem "bcachefs" config.boot.initrd.supportedFilesystems) || (bootFs != {})) {
            '';
            licenses = toFile "licenses.patch" ''
diff --git a/lib/licenses.nix b/lib/licenses.nix
index 4fa6d6abc7a..198b570e0ae 100644
--- a/lib/licenses.nix
+++ b/lib/licenses.nix
@@ -690,6 +690,11 @@ in mkLicense lset) ({
     fullName = "OpenSSL License";
   };
 
+  oreo = {
+    fullName = "Oreo Public License";
+    free = true;
+  };
+
   osl2 = {
     spdxId = "OSL-2.0";
     fullName = "Open Software License 2.0";
            '';
            python = toFile "python.patch" ''
diff --git a/pkgs/top-level/aliases.nix b/pkgs/top-level/aliases.nix
index 7b9c55ee702..4c86533cad5 100644
--- a/pkgs/top-level/aliases.nix
+++ b/pkgs/top-level/aliases.nix
@@ -1154,10 +1154,10 @@ mapAliases ({
   pyrex095 = throw "pyrex has been removed from nixpkgs as the project is still stuck on python2"; # Added 2022-01-12
   pyrex096 = throw "pyrex has been removed from nixpkgs as the project is still stuck on python2"; # Added 2022-01-12
   pyrit = throw "pyrit has been removed from nixpkgs as the project is still stuck on python2"; # Added 2022-01-01
-  python = python2; # Added 2022-01-11
+  python = python3; # Added 2022-01-11
   python-swiftclient = swiftclient; # Added 2021-09-09
   python2nix = throw "python2nix has been removed as it is outdated. Use e.g. nixpkgs-pytools instead"; # Added 2021-03-08
-  pythonFull = python2Full; # Added 2022-01-11
+  pythonFull = python3Full; # Added 2022-01-11
   pythonPackages = python.pkgs; # Added 2022-01-11
 
   ### Q ###
diff --git a/pkgs/top-level/all-packages.nix b/pkgs/top-level/all-packages.nix
index 1803508bdd4..da416ccaea6 100644
--- a/pkgs/top-level/all-packages.nix
+++ b/pkgs/top-level/all-packages.nix
@@ -14502,7 +14502,7 @@ with pkgs;
   # available as `pythonPackages.tkinter` and can be used as any other Python package.
   # When switching these sets, please update docs at ../../doc/languages-frameworks/python.md
   python2 = python27;
-  python3 = python39;
+  python3 = python310;
 
   # pythonPackages further below, but assigned here because they need to be in sync
   python2Packages = dontRecurseIntoAttrs python27Packages;
            '';
        };
        overlayset = with lib; rec {
            nodeOverlays = mapAttrs (n: j.update.node.default) callPackages.node;
            pythonOverlays = rec {
                python2 = j.foldToSet [
                    (mapAttrs j.update.python.callPython.two callPackages.python.two)
                ];
                python3 = let
                    update = j.update.python.package.three;
                in j.foldToSet [
                    {
                        hy = final: update "hy" (old: rec {
                            version = "0.24.0";
                            src = final.fetchFromGitHub {
                                owner = "hylang";
                                repo = old.pname;
                                rev = version;
                                sha256 = "1s458ymd9g3s8k2ccc300jr4w66c7q3vhmhs9z3d3a4qg0xdhs9y";
                            };
                            postPatch = ''substituteInPlace setup.py --replace "\"funcparserlib ~= 1.0\"," ""'' + (old.postPatch or "");
                            disabledTestPaths = [ "tests/test_bin.py" ] ++ (old.disabledTestPaths or []);
                        });
                        hyrule = final: update "hyrule" (old: rec {
                            version = "0.2";
                            src = final.fetchFromGitHub {
                                owner = "hylang";
                                repo = old.pname;
                                rev = version;
                                sha256 = "08w4q8s1hrnjqsqvs70adx90nqfij6iyyb4fzfffrrw2mwkf10gx";
                            };
                            postPatch = ''substituteInPlace setup.py --replace "'hy == 0.24.0'," ""'' + (old.postPatch or "");
                        });
                        flit = final: update "flit" (old: with final; let newInputs = [ git ]; in {
                            buildInputs = newInputs ++ (old.buildInputs or []);
                            nativeBuildInputs = newInputs ++ (old.nativeBuildInputs or []);
                            disabledTestPaths = [
                                "tests/test_sdist.py"
                                "tests/test_upload.py"
                            ] ++ (old.disabledTestPaths or []);
                        });
                    }
                    (mapAttrs j.update.python.callPython.three callPackages.python.three)
                ];
                python = python3;
                xonsh = j.foldToSet [
                    (mapAttrs j.update.python.callPython.three callPackages.python.xonsh)
                ];
            };
            overlays = let
                calledPackages = mapAttrs (n: v: final: prev: { "${n}" = final.callPackage v {}; }) (filterAttrs (n: v: isFunction v) callPackages);
                overlay = final: prev: { inherit (calledPackages) settings; };
            in j.foldToSet [
                pythonOverlays.python2
                pythonOverlays.python3
                pythonOverlays.xonsh
                calledPackages
                (let pkgsets = {
                    # nixos-unstable = [ "gnome-tour" ];
                    # nixos-unstable = "gnome-tour";
                    # nixos-unstable = { python3 = "python310"; };
                };
                in mapAttrsToList (
                    pkgchannel: pkglist': let
                        pkglist = if (isString pkglist') then [ pkglist' ] else pkglist';
                    in map (
                        pkg': let
                            pkgIsAttrs = isAttrs pkg';
                            pkg1 = if pkgIsAttrs then (last (attrNames pkg')) else pkg';
                            pkg2 = if pkgIsAttrs then (last (attrValues pkg')) else pkg';
                            self = (pkgchannel == channel) || (pkgchannel == "self");
                        in final: prev: { "${pkg1}" = if self then (if pkgIsAttrs then final.${pkg2} else prev.${pkg2}) else inputs.${pkgchannel}.legacyPackages.${final.stdenv.targetPlatform.system}.${pkg2}; }
                    ) pkglist
                ) pkgsets)
                (let pkgsets = {
                    # nixos-unstable = [ { python310Packages = "mypy"; } { python310Packages = [ "mypy" ]; } ];
                    # nixos-unstable = { python310Packages = "mypy"; };
                    # nixos-unstable = { python310Packages = [ "mypy" ]; };
                };
                in mapAttrsToList (
                    pkgchannel: pkglist': let
                        pkglist = if (isAttrs pkglist') then [ pkglist' ] else pkglist';
                    in map (
                        pkg': let
                            pkg1 = last (attrNames pkg');
                            pkg2Pre = last (attrValues pkg');
                            pkg2IsString = isString pkg2Pre;
                            self = (pkgchannel == channel) || (pkgchannel == "self");
                            pkgFunc = pkg: { "${pkg}" = if self then (if pkgIsAttrs then final.${pkg} else prev.${pkg}) else inputs.${pkgchannel}.legacyPackages.${final.stdenv.targetPlatform.system}.${pkg1}.${pkg}; };
                            pkg2 = if pkg2IsString then (pkgFunc pkg2Pre) else (genAttrs pkg2Pre pkgFunc);
                        in final: prev: { "${pkg1}" = pkg2; }
                    ) pkglist
                ) pkgsets)
                {
                    nodeEnv = final: prev: { nodeEnv = final.callPackage "${inputs.node2nix}/nix/node-env.nix" {}; };
                    systemd = final: prev: { systemd = prev.systemd.overrideAttrs (old: { withHomed = true; }); };
                    emacs = inputs.emacs.overlay;
                    nur = final: prev: { nur = import inputs.nur { nurpkgs = inputs.nixpkgs; pkgs = final; }; };
                    # nix = inputs.nix.overlay;
                    nix-direnv = final: prev: { nix-direnv = prev.nix-direnv.override { enableFlakes = true; }; };
                    lib = final: prev: { inherit lib; };
                    default = overlay;
                    Python = final: prev: rec {
                        Python2 = final.${j.attrs.versions.python.two};
                        Python2Packages = Python2.pkgs;
                        Python3 = final.${j.attrs.versions.python.three};
                        Python3Packages = Python3.pkgs;
                        Python = Python3;
                        PythonPackages = Python3Packages;
                    };
                }
            ];
            inherit overlay;
            defaultOverlay = overlay;
        };
        profiles = {
            server = { config, pkgs, ... }: let
                relayNo = if config.variables.relay then "no" else "yes";
                relayYes = if config.variables.relay then "yes" else "no";
            in {
                imports = attrValues nixosModules;
                environment.systemPackages = with pkgs; [ inetutils mtr sysstat git ];
                variables.server = true;
            };
        };
        devices = {
            linode = { config, ... }: {
                imports = flatten [
                    profiles.server
                    "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
                ];
                boot = {
                    kernelParams = [ "console=ttyS0,19200n8" ];
                    loader.grub.extraConfig = ''
                        serial --speed=19200 --unit=0 --word=8 --parity=no --stop=1;
                        terminal_input serial;
                        terminal_output serial;
                    '';
                    initrd.availableKernelModules = [ "virtio_pci" "ahci" "sd_mod" ];
                };
                networking = {
                    usePredictableInterfaceNames = false;
                    interfaces.eth0.useDHCP = true;
                };
            };
            rpi3 = { config, pkgs, ... }: {
                imports =  toList profiles.server;
                hardware.enableRedistributableFirmware = true;
                networking.wireless.enable = true;
                sound.enable = true;
                hardware.pulseaudio.enable = mkForce true;
                boot.kernelParams = toList "console=ttyS1,115200n8";
                boot.loader.raspberryPi = {
                    enable = true;
                    version = 3;
                    firmwareConfig = ''
                        dtparam=audio=on
                        core_freq=250
                        start_x=1
                        gpu_mem=256
                    '';
                    uboot.enable = true;
                };
                systemd.services.btattach = {
                    before = [ "bluetooth.service" ];
                    after = [ "dev-ttyAMA0.device" ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                        ExecStart = "${pkgs.bluez}/bin/btattach -B /dev/ttyAMA0 -P bcm -S 3000000";
                    };
                };
                boot.kernelModules = [ "bcm2835-v4l2" ];
                boot.initrd.kernelModules = [ "vc4" "bcm2835_dma" "i2c_bcm2835" ];
            };
            rpi4 = { config, pkgs, ... }: {
                imports =  flatten [
                    profiles.server
                    inputs.hardware.raspberry-pi-4
                ];
                boot.kernelPackages = mkForce pkgs.linuxPackages_rpi4;
            };
        };
        nixosModules = with lib; rec {
            nixosModules = rec {
                openssh = { config, ... }: {
                    services.openssh = {
                        enable = true;
                        extraConfig = mkOrder 0 ''
                            TCPKeepAlive yes
                            ClientAliveCountMax 480
                            ClientAliveInterval 3m
                        '';
                        permitRootLogin = "yes";
                        openFirewall = config.variables.relay;
                    };
                };
                options = { config, options, pkgs, ... }: {
                    options = {
                        variables = {
                            zfs = mkOption {
                                type = types.bool;
                                default = true;
                            };
                            relay = mkOption {
                                type = types.bool;
                                default = false;
                            };
                            server = mkOption {
                                type = types.bool;
                                default = config.variables.relay;
                            };
                            client = mkOption {
                                type = types.bool;
                                default = (! config.variables.server) && (! config.variables.relay);
                            };
                            minimal = mkOption {
                                type = types.bool;
                                default = false;
                            };
                            encrypted = mkOption {
                                type = types.bool;
                                default = false;
                            };
                        };
                        programs = {
                            mosh = {
                                openFirewall = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Whether to automatically open the specified port in the firewall.";
                                };
                            };
                        };
                        services = {
                            tailscale = {
                                autoconnect = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Automatically run `tailscale up' on boot.";
                                };
                                openFirewall = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Whether to automatically open the specified port in the firewall.";
                                };
                                trustInterface = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Whether to automatically trust the specified interface in the firewall.";
                                };
                                hostName = mkOption {
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "The hostname for this device; defaults to `config.networking.hostName'.";
                                };
                                useUUID = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Use a new UUID as the hostname on every boot; enables `config.services.tailscale.api.ephemeral' by default.";
                                };
                                deleteHostBeforeAuth = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = ''
                                        Delete the hostname from the tailnet before authentication, if it exists.
                                        Does nothing if already authenticated.
                                    '';
                                };
                                strictReversePathFiltering = mkOption {
                                    type = types.bool;
                                    default = true;
                                    description = "Whether to enable strict reverse path filtering.";
                                };
                                authkey = mkOption {
                                    type = types.nullOr types.nonEmptyStr;
                                    default = null;
                                    description = ''
                                        Authentication key.

                                        Warning: Consider using authfile instead if you do not
                                        want to store the key in the world-readable Nix store.
                                    '';
                                };
                                authfile = mkOption {
                                    example = "/private/tailscale_auth_key";
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "File with authentication key.";
                                };
                                api.key = mkOption {
                                    type = types.nullOr types.nonEmptyStr;
                                    default = null;
                                    description = ''
                                        API key.

                                        Warning: Consider using api.file instead if you do not
                                        want to store the key in the world-readable Nix store.
                                    '';
                                };
                                api.file = mkOption {
                                    example = "/private/tailscale_api_key";
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "File with API key.";
                                };
                                api.tags = mkOption {
                                    example = [ "relay" "server" ];
                                    type = types.listOf types.nonEmptyStr;
                                    default = [ ];
                                    description = "Tags to be used when creating new auth keys.";
                                };
                                api.reusable = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Create a reusable auth key.";
                                };
                                api.ephemeral = mkOption {
                                    type = with types; nullOr bool;
                                    default = null;
                                    description = "Create an ephemeral auth key; is enabled by default by `config.services.tailscale.useUUID'.";
                                };
                                api.preauthorized = mkOption {
                                    type = types.bool;
                                    default = true;
                                    description = "Create a pre-authorized auth key.";
                                };
                                api.domain = mkOption {
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "Your tailscale domain.";
                                };
                                state.text = mkOption {
                                    type = types.nullOr types.lines;
                                    default = null;
                                    description = ''
                                        The state of tailscale, written to /var/lib/tailscale/tailscaled.state

                                        Warning: Consider using state.{file|dir} instead if you do not
                                        want to store the state in the world-readable Nix store.
                                    '';
                                };
                                state.file = mkOption {
                                    example = "/private/tailscale/tailscaled.state";
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "File with the state of tailscale.";
                                };
                                state.dir = mkOption {
                                    example = "/private/tailscale";
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "Directory with the state file (tailscaled.state) of tailscale.";
                                };
                                magicDNS.enable = mkEnableOption "MagicDNS";
                                magicDNS.searchDomains = mkOption {
                                    type = types.listOf types.nonEmptyStr;
                                    default = [ ];
                                    description = "MagicDNS search domains.";
                                };
                                magicDNS.nameservers = mkOption {
                                    type = types.listOf types.nonEmptyStr;
                                    default = [ ];
                                    description = "MagicDNS nameservers.";
                                };
                                acceptDNS = mkOption {
                                    type = types.bool;
                                    default = true;
                                    description = "Whether this tailscale instance will use the preconfigured DNS servers on the tailscale admin page.";
                                };
                                routes.accept = mkOption {
                                    type = with types; nullOr bool;
                                    default = null;
                                    description = "Use subnet routers; enabled by default if `config.services.tailscale.routes.advertise' is null.";
                                };
                                routes.advertise = mkOption {
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "Start tailscale as a subnet router with the specified subnets.";
                                };
                                exitNode.advertise = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Whether this tailscale instance will used as an exit node.";
                                };
                                exitNode.ip = mkOption {
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "The exit node, as an ip address, to be used with this device.";
                                };
                                exitNode.hostName = mkOption {
                                    type = with types; nullOr nonEmptyStr;
                                    default = null;
                                    description = "The exit node, as a hostname, to be used with this device; requires an api key provided via `config.services.tailscale.api.{key|file}'.";
                                };
                                exitNode.allowLANAccess = mkOption {
                                    type = types.bool;
                                    default = false;
                                    description = "Allow direct access to your local network when traffic is routed via an exit node.";
                                };
                                extraConfig = mkOption {
                                    type = types.attrs;
                                    default = { };
                                    description = "An attribute set of options and values; if an option is a single character, a single dash will be prepended, otherwise two.";
                                };
                            };
                            guix = {
                                enable = mkEnableOption "GNU Guix package manager";
                                package = mkOption {
                                    type = types.package;
                                    default = pkgs.guix;
                                    defaultText = "pkgs.guix";
                                    description = "Package that contains the guix binary and initial store.";
                                };
                            };
                        };
                    };
                };
                imports = [ ./var ];
                config = mkMerge [
                    { _module.args.variables = config.variables; }
                    (let cfg = config.programs.mosh; in mkIf cfg.enable {
                        networking.firewall.allowedUDPPortRanges = optional cfg.openFirewall { from = 60000; to = 61000; };
                    })
                    (let cfg = config.services.guix; in mkIf cfg.enable {
                        users = {
                            extraUsers = lib.fold (a: b: a // b) {} (builtins.map buildGuixUser (lib.range 1 10));
                            extraGroups.guixbuild = {name = "guixbuild";};
                        };
                        systemd.services.guix-daemon = {
                            enable = true;
                            description = "Build daemon for GNU Guix";
                            serviceConfig = {
                                ExecStart="/var/guix/profiles/per-user/root/current-guix/bin/guix-daemon --build-users-group=guixbuild";
                                Environment="GUIX_LOCPATH=/var/guix/profiles/per-user/root/guix-profile/lib/locale";
                                RemainAfterExit="yes";

                                # See <https://lists.gnu.org/archive/html/guix-devel/2016-04/msg00608.html>.
                                # Some package builds (for example, go@1.8.1) may require even more than
                                # 1024 tasks.
                                TasksMax="8192";
                            };
                            wantedBy = [ "multi-user.target" ];
                        };
                        system.activationScripts.guix = ''
                            # copy initial /gnu/store
                            if [ ! -d /gnu/store ]
                            then
                                mkdir -p /gnu
                                cp -ra ${cfg.package.store}/gnu/store /gnu/
                            fi

                            # copy initial /var/guix content
                            if [ ! -d /var/guix ]
                            then
                                mkdir -p /var
                                cp -ra ${cfg.package.var}/var/guix /var/
                            fi

                            # root profile
                            if [ ! -d ~root/.config/guix ]
                            then
                                mkdir -p ~root/.config/guix
                                ln -sf /var/guix/profiles/per-user/root/current-guix \
                                ~root/.config/guix/current
                            fi

                            # authorize substitutes
                            GUIX_PROFILE="`echo ~root`/.config/guix/current"; source $GUIX_PROFILE/etc/profile
                            guix archive --authorize < ~root/.config/guix/current/share/guix/ci.guix.info.pub
                        '';

                        environment.shellInit = ''
                            # Make the Guix command available to users
                            export PATH="/var/guix/profiles/per-user/root/current-guix/bin:$PATH"

                            export GUIX_LOCPATH="$HOME/.guix-profile/lib/locale"
                            export PATH="$HOME/.guix-profile/bin:$PATH"
                            export INFOPATH="$HOME/.guix-profile/share/info:$INFOPATH"
                        '';
                    })
                    (let cfg = config.services.tailscale; in mkIf cfg.enable {
                        assertions = flatten [
                            (optional ((count (state: state != null) (with cfg.state; [ text file dir ])) > 1)
                                      "Sorry; only one of `config.services.tailscale.state.{text|file|dir}' may be set!")
                            (optional ((cfg.exitNode.ip != null) && (cfg.exitNode.hostName != null))
                                      "Sorry; only one of `config.services.tailscale.exitNode.{ip|hostName}' may be set!")
                            (optional ((cfg.exitNode.hostName != null) && (cfg.api.key == null) && (cfg.api.file == null))
                                      "Sorry; `config.services.tailscale.api.{key|file}' must be set when using `config.services.tailscale.exitNode.hostName'!")
                            (optional ((count (auth: auth != null) (with cfg; [ authkey authfile api.key api.file ])) > 1)
                                      "Sorry; only one of `config.services.tailscale.{authkey|authfile|api.key|api.file}' may be set!")
                            (optional ((cfg.api.domain == null) && ((cfg.api.key != null) || (cfg.api.file != null)))
                                      "Sorry; `config.services.tailscale.api.domain' must be set when using `config.services.tailscale.api.{key|file}'!")
                        ];
                        warnings = flatten [
                            (optional (cfg.exitNode.advertise && cfg.acceptDNS)
                                      "Advertising this device as an exit node and accepting the preconfigured DNS servers on the tailscale admin page at the same time may result in this device attempting to use itself as a DNS server.")

                            # TODO: Why is this causing an infinite recursion error?
                            # (optional (((isBool cfg.routes.accept) && cfg.routes.accept) && (cfg.routes.advertise != null))
                            #           "Advertising this device as a subnet router and accepting the preconfigured subnet routes on the tailscale admin page at the same time may result in this device #TODO")

                        ];
                        services.tailscale = {
                            api.ephemeral = if (cfg.api.ephemeral == null) then config.services.tailscale.useUUID else cfg.api.ephemeral;
                            hostName = if (cfg.hostName == null) then config.networking.hostName else cfg.hostName;
                            routes.accept = if (cfg.routes.accept == null) then (cfg.routes.advertise == null) else cfg.routes.accept;
                        };
                        environment.vars = let
                            nullText = cfg.state.text != null;
                            nullFile = cfg.state.file != null;
                            nullDir = cfg.state.dir != null;
                        in optionalAttrs (nullText || nullFile || nullDir) {
                            "lib/tailscale/tailscaled.state" = mkIf (nullText || nullFile) {
                                ${if nullText then "text" else "source"} = if (nullText) then cfg.state.text else cfg.state.file;
                            };
                            "lib/tailscale" = mkIf nullDir { source = cfg.state.dir; };
                        };
                        networking = {
                            nameservers = optionals cfg.magicDNS.enable (flatten [ cfg.magicDNS.nameservers "100.100.100.100" ]);
                            search = optionals cfg.magicDNS.enable cfg.magicDNS.searchDomains;
                            firewall = {
                                ${if cfg.strictReversePathFiltering then null else "checkReversePath"} = "loose";
                                trustedInterfaces = optional cfg.trustInterface cfg.interfaceName;
                                allowedUDPPorts = optional cfg.openFirewall cfg.port;
                            };
                        };
                        systemd.services.tailscale-autoconnect = mkIf cfg.autoconnect {
                            description = "Automatic connection to Tailscale";

                            # make sure tailscale is running before trying to connect to tailscale
                            after = [ "network-pre.target" "tailscale.service" ];
                            wants = [ "network-pre.target" "tailscale.service" ];
                            wantedBy = [ "multi-user.target" ];

                            environment.TAILSCALE_APIKEY = if (cfg.api.key != null) then cfg.api.key else (readFile cfg.api.file);

                            # set this service as a oneshot job
                            serviceConfig = {
                                Type = "oneshot";
                                ExecStart = let
                                    extraConfig = mapAttrsToList (opt: val: let
                                        value = optionalString (! (isBool val)) " ${toString val}";
                                    in (if ((stringLength opt) == 1) then "-" else "--") + opt + value) cfg.extraConfig;
                                    connect = authenticating: ''
                                        # otherwise connect to ${optionalString authenticating "and authenticate with "}tailscale
                                        echo "Connecting to ${optionalString authenticating "and authenticating with "}Tailscale ..."
                                        ${cfg.package}/bin/tailscale up --hostname ${if cfg.useUUID then "$(${pkgs.util-linux}/bin/uuidgen)" else cfg.hostName} \
                                        ${optionalString cfg.acceptDNS "--accept-dns \\"}
                                        ${optionalString cfg.routes.accept "--accept-routes \\"}
                                        ${optionalString (cfg.routes.advertise != null) "--advertise-routes ${cfg.routes.advertise} \\"}
                                        ${optionalString cfg.exitNode.advertise "--advertise-exit-node \\"}
                                        ${optionalString (cfg.exitNode.ip != null) "--exit-node ${cfg.exitNode.ip} \\"}
                                        ${optionalString (cfg.exitNode.hostName != null) ''--exit-node $(${pkgs.tailapi}/bin/tailapi --domain ${cfg.api.domain} \
                                                                                           --recreate-response \
                                                                                           --devices ${cfg.exitNode.hostName} \
                                                                                           ip -f4) \''}
                                        ${optionalString (((cfg.exitNode.ip != null) || (cfg.exitNode.hostName != null)) && cfg.exitNode.allowLANAccess)
                                                         "--exit-node-allow-lan-access \\"}

                                        ${concatStringsSep " " (mapAttrsToList (n: v: let
                                            opt = (if ((stringLength n) == 1) then "-" else "--") + n;
                                        in "${opt} ${v}") extraConfig)} \

                                        ${optionalString (authenticating && (cfg.authkey != null)) "--authkey ${cfg.authkey} \\"}
                                        ${optionalString (authenticating && (cfg.authfile != null)) "--authkey ${readFile cfg.authfile} \\"}
                                        ${optionalString authenticating ''--authkey $(${pkgs.tailapi}/bin/tailapi --domain ${cfg.api.domain} \
                                                                                                                  --recreate-response \
                                                                                                                  create \
                                                                                                                  ${optionalString cfg.api.reusable "--reusable \\"}
                                                                                                                  ${optionalString cfg.api.ephemeral "--ephemeral \\"}
                                                                                                                  ${optionalString cfg.api.reusable "--preauthorized \\"}
                                                                                                                  ${optionalString (cfg.api.tags != null)
                                                                                                                                   (concatStringsSep " " cfg.api.tags)} \
                                                                                                                  --just-key)''}
                                    '';
                                in ''
                                    # wait for tailscaled to settle
                                    sleep 2

                                    # check if we are already connected to tailscale
                                    echo "Waiting for tailscale.service start completion ..."
                                    status="$(${cfg.package}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"
                                    if [ $status = "Running" ]; then # if so, then do nothing
                                        echo "Already connected to Tailscale, exiting."
                                        exit 0
                                    fi

                                    # Delete host from tailnet if:
                                    # * `config.services.tailscale.deleteHostBeforeAuth' is enabled
                                    # * `config.services.tailscale.api.{key|file}' is not null
                                    # * tailscale is not authenticated
                                    if [ $status = "NeedsLogin" ]; then
                                        ${if cfg.deleteHostBeforeAuth then ''${pkgs.coreutils}/bin/cat <<EOF
                                                                             Because `config.services.tailscale.deleteHostBeforeAuth' has been enabled,
                                                                             any devices with hostname "${config.networking.hostName}" will be deleted before authentication.
                                                                             EOF''
                                                                      else ''${pkgs.coreutils}/bin/cat <<EOF
                                                                             Because `config.services.tailscale.deleteHostBeforeAuth' has not been enabled,
                                                                             any devices with hostname "${config.networking.hostName}" will not be deleted before authentication.
                                                                             EOF''}
                                        ${optionalString cfg.deleteHostBeforeAuth ''${pkgs.tailapi}/bin/tailapi --domain ${cfg.api.domain} \
                                                                                                                --recreate-response \
                                                                                                                --devices ${cfg.hostName} \
                                                                                                                delete \
                                                                                                                --do-not-prompt &> /dev/null && \
                                                                                    echo Successfully deleted device of hostname \"${config.networking.hostName}\"!"''}
                                    fi

                                    if [ $status = "NeedsLogin" ]; then
                                        ${connect true}
                                    else
                                        ${connect false}
                                    fi

                                    ${optionalString ((cfg.state.file != null) && (! (pathExists cfg.state.file))) "cp /var/lib/tailscale/tailscaled.state ${cfg.state.file}"}
                                    ${optionalString ((cfg.state.dir != null) && ((! (pathExists cfg.state.dir)) || ((length (attrNames (readDir cfg.state.dir))) == 0)))
                                                     "${pkgs.rsync}/bin/rsync -avvczz /var/lib/tailscale/ ${cfg.state.dir}/"}
                                '';
                            };
                        };
                    })
                ];
            };
            default = options;
            var = { config, pkgs, ... }: let
                var' = filter (f: f.enable) (attrValues config.environment.vars);
                var = pkgs.runCommandLocal "var" {
                    # This is needed for the systemd module
                    passthru.targets = map (x: x.target) var';
                } /* sh */ ''
                    set -euo pipefail

                    makevarEntry() {
                        src="$1"
                        target="$2"
                        mode="$3"
                        user="$4"
                        group="$5"

                        if [[ "$src" = *'*'* ]]; then
                            # If the source name contains '*', perform globbing.
                            mkdir -p "$out/var/$target"
                            for fn in $src; do
                                ln -s "$fn" "$out/var/$target/"
                            done
                        else
                            mkdir -p "$out/var/$(dirname "$target")"
                            if ! [ -e "$out/var/$target" ]; then
                                ln -s "$src" "$out/var/$target"
                            else
                                echo "duplicate entry $target -> $src"
                                if [ "$(readlink "$out/var/$target")" != "$src" ]; then
                                    echo "mismatched duplicate entry $(readlink "$out/var/$target") <-> $src"
                                    ret=1
                                    continue
                                fi
                            fi
                            if [ "$mode" != symlink ]; then
                                echo "$mode" > "$out/var/$target.mode"
                                echo "$user" > "$out/var/$target.uid"
                                echo "$group" > "$out/var/$target.gid"
                            fi
                        fi
                    }

                    mkdir -p "$out/var"
                    ${concatMapStringsSep "\n" (varEntry: escapeShellArgs [
                        "makevarEntry"
                        # Force local source paths to be added to the store
                        "${varEntry.source}"
                        varEntry.target
                        varEntry.mode
                        varEntry.user
                        varEntry.group
                    ]) var'}
                '';
                setup-var = toFile "setup.var.pl" ''
use strict;
use File::Find;
use File::Copy;
use File::Path;
use File::Basename;
use File::Slurp;

my $var = $ARGV[0] or die;
my $static = "/var/static";

sub atomicSymlink {
    my ($source, $target) = @_;
    my $tmp = "$target.tmp";
    unlink $tmp;
    symlink $source, $tmp or return 0;
    rename $tmp, $target or return 0;
    return 1;
}


# Atomically update /var/static to point at the var files of the
# current configuration.
atomicSymlink $var, $static or die;

# Returns 1 if the argument points to the files in /var/static.  That
# means either argument is a symlink to a file in /var/static or a
# directory with all children being static.
sub isStatic {
    my $path = shift;

    if (-l $path) {
        my $target = readlink $path;
        return substr($target, 0, length "/var/static/") eq "/var/static/";
    }

    if (-d $path) {
        opendir DIR, "$path" or return 0;
        my @names = readdir DIR or die;
        closedir DIR;

        foreach my $name (@names) {
            next if $name eq "." || $name eq "..";
            unless (isStatic("$path/$name")) {
                return 0;
            }
        }
        return 1;
    }

    return 0;
}

# Remove dangling symlinks that point to /var/static.  These are
# configuration files that existed in a previous configuration but not
# in the current one.  For efficiency, don't look under /var/nixos
# (where all the NixOS sources live).
sub cleanup {
    if ($File::Find::name eq "/var/nixos") {
        $File::Find::prune = 1;
        return;
    }
    if (-l $_) {
        my $target = readlink $_;
        if (substr($target, 0, length $static) eq $static) {
            my $x = "/var/static/" . substr($File::Find::name, length "/var/");
            unless (-l $x) {
                print STDERR "removing obsolete symlink ‘$File::Find::name’...\n";
                unlink "$_";
            }
        }
    }
}

find(\&cleanup, "/var");


# Use /var/.clean to keep track of copied files.
my @oldCopied = read_file("/var/.clean", chomp => 1, err_mode => 'quiet');
open CLEAN, ">>/var/.clean";


# For every file in the var tree, create a corresponding symlink in
# /var to /var/static.  The indirection through /var/static is to make
# switching to a new configuration somewhat more atomic.
my %created;
my @copied;

sub link {
    my $fn = substr $File::Find::name, length($var) + 1 or next;
    my $target = "/var/$fn";
    File::Path::make_path(dirname $target);
    $created{$fn} = 1;

    # Rename doesn't work if target is directory.
    if (-l $_ && -d $target) {
        if (isStatic $target) {
            rmtree $target or warn;
        } else {
            warn "$target directory contains user files. Symlinking may fail.";
        }
    }

    if (-e "$_.mode") {
        my $mode = read_file("$_.mode"); chomp $mode;
        if ($mode eq "direct-symlink") {
            atomicSymlink readlink("$static/$fn"), $target or warn;
        } else {
            my $uid = read_file("$_.uid"); chomp $uid;
            my $gid = read_file("$_.gid"); chomp $gid;
            copy "$static/$fn", "$target.tmp" or warn;
            $uid = getpwnam $uid unless $uid =~ /^\+/;
            $gid = getgrnam $gid unless $gid =~ /^\+/;
            chown int($uid), int($gid), "$target.tmp" or warn;
            chmod oct($mode), "$target.tmp" or warn;
            rename "$target.tmp", $target or warn;
        }
        push @copied, $fn;
        print CLEAN "$fn\n";
    } elsif (-l "$_") {
        atomicSymlink "$static/$fn", $target or warn;
    }
}

find(\&link, $var);


# Delete files that were copied in a previous version but not in the
# current.
foreach my $fn (@oldCopied) {
    if (!defined $created{$fn}) {
        $fn = "/var/$fn";
        print STDERR "removing obsolete file ‘$fn’...\n";
        unlink "$fn";
    }
}


# Rewrite /var/.clean.
close CLEAN;
write_file("/var/.clean", map { "$_\n" } @copied);

# Create /var/NIXOS tag if not exists.
# When /var is not on a persistent filesystem, it will be wiped after reboot,
# so we need to check and re-create it during activation.
open TAG, ">>/var/NIXOS";
close TAG;
                '';
            in {
                options = {
                    environment.vars = mkOption {
                        default = {};
                        example = literalExpression ''
                            { example-configuration-file =
                                { source = "/nix/store/.../var/dir/file.conf.example";
                                mode = "0440";
                                };
                            "default/useradd".text = "GROUP=100 ...";
                            }
                        '';
                        description = ''
                            Set of files that have to be linked in <filename>/var</filename>.
                        '';
                        type = with types; attrsOf (submodule (
                            { name, config, options, ... }:
                            { options = {
                                enable = mkOption {
                                    type = types.bool;
                                    default = true;
                                    description = ''
                                        Whether this /var file should be generated.  This
                                        option allows specific /var files to be disabled.
                                    '';
                                };
                                target = mkOption {
                                    type = types.str;
                                    description = ''
                                        Name of symlink (relative to
                                        <filename>/var</filename>).  Defaults to the attribute
                                        name.
                                    '';
                                };
                                text = mkOption {
                                    default = null;
                                    type = types.nullOr types.lines;
                                    description = "Text of the file.";
                                };
                                source = mkOption {
                                    type = types.path;
                                    description = "Path of the source file.";
                                };
                                mode = mkOption {
                                    type = types.str;
                                    default = "symlink";
                                    example = "0600";
                                    description = ''
                                        If set to something else than <literal>symlink</literal>,
                                        the file is copied instead of symlinked, with the given
                                        file mode.
                                    '';
                                };
                                uid = mkOption {
                                    default = 0;
                                    type = types.int;
                                    description = ''
                                        UID of created file. Only takes effect when the file is
                                        copied (that is, the mode is not 'symlink').
                                    '';
                                };
                                gid = mkOption {
                                    default = 0;
                                    type = types.int;
                                    description = ''
                                        GID of created file. Only takes effect when the file is
                                        copied (that is, the mode is not 'symlink').
                                    '';
                                };
                                user = mkOption {
                                    default = "+${toString config.uid}";
                                    type = types.str;
                                    description = ''
                                        User name of created file.
                                        Only takes effect when the file is copied (that is, the mode is not 'symlink').
                                        Changing this option takes precedence over <literal>uid</literal>.
                                    '';
                                };
                                group = mkOption {
                                    default = "+${toString config.gid}";
                                    type = types.str;
                                    description = ''
                                        Group name of created file.
                                        Only takes effect when the file is copied (that is, the mode is not 'symlink').
                                        Changing this option takes precedence over <literal>gid</literal>.
                                    '';
                                };
                            };
                            config = {
                                target = mkDefault name;
                                source = mkIf (config.text != null) (
                                    let name' = "var-" + baseNameOf name;
                                    in mkDerivedConfig options.text (pkgs.writeText name')
                                );
                            };
                        }));
                    };
                };
                config = {
                    system = {
                        activationScripts.vars = lib.stringAfter [ "users" "groups" ] config.system.build.varActivationCommands;
                        build = {
                            var = var;
                            varActivationCommands = ''
                                # Set up the statically computed bits of /var.
                                echo "setting up /var..."
                                ${pkgs.perl.withPackages (p: [ p.FileSlurp ])}/bin/perl ${setup-var} ${var}/var
                            '';
                        };
                    };
                };
            };
            nixosModule = nixosModules.default;
            defaultNixosModule = nixosModule;
        };
        templates = rec {
            templates = rec {
                general = {
                    description = "The general template for all our programs!";
                    path = toFile "general-template.nix" ''
{

    # TODO: Change this!
    description = "";

    inputs = {
        settings.url = github:sylvorg/settings;
        nixpkgs.follows = "settings/nixpkgs";
        flake-utils.url = github:numtide/flake-utils;
        flake-compat = {
            url = "github:edolstra/flake-compat";
            flake = false;
        };
    };
    outputs = inputs@{ self, nixpkgs, flake-utils, settings, ... }: with builtins; with settings.lib; with flake-utils.lib; let

        # TODO: Change this!
        pname = "";

        # TODO: Change this!
        callPackage = {}: {};

        overlayset = let
            overlay = final: prev: { "${pname}" = final.callPackage callPackage {}; };
        in rec {
            overlays = settings.overlays // { default = overlay; "${pname}" = overlay; };
            overlay = overlays.default;
            defaultOverlay = overlay;
        };
    in j.foldToSet [
        (eachSystem allSystems (system: let
            made = make system (attrValues overlayset.overlays);
        in rec {
            inherit (made) legacyPackages;
            packages = flattenTree { default = legacyPackages.${pname}; "${pname}" = legacyPackages.${pname}; };
            package = packages.default;
            defaultPackage = package;
            apps = mapAttrs (n: made.app) packages;
            app = apps.default;
            defaultApp = app;
            devShells = j.foldToSet [
                (mapAttrs (n: v: legacyPackages.mkShell { buildInputs = toList v; }) packages)
                { default = legacyPackages.mkShell { buildInputs = unique (attrValues packages); }; }
            ];
            devShell = devShells.default;
            defaultdevShell = devShell;
        }))
        overlayset
        { inherit pname callPackage; }
    ];
}
                    '';
                };
                python = toFile "python-template.nix" ''
{

    # TODO: Change this!
    description = "";

    inputs = {
        settings.url = github:sylvorg/settings;
        nixpkgs.follows = "settings/nixpkgs";
        flake-utils.url = github:numtide/flake-utils;
        flake-compat = {
            url = "github:edolstra/flake-compat";
            flake = false;
        };
    };
    outputs = inputs@{ self, nixpkgs, flake-utils, settings, ... }: with builtins; with settings.lib; with flake-utils.lib; let

        # TODO: Change this!
        pname = "";

        # TODO: Change this!
        callPackage = {}: {};

        overlayset = let
            overlay = j.update.python.callPython.three pname callPackage;
        in rec {
            overlays = settings.overlays // { default = overlay; "${pname}" = overlay; };
            inherit overlay;
            defaultOverlay = overlay;
        };
    in j.foldToSet [
        (eachSystem allSystems (system: let
            made = settings.make system (attrValues overlayset.overlays);
            python = made.mkPython made.legacyPackages.Python3 [] pname;
            xonsh = made.mkXonsh [] pname;
        in rec {
            inherit (settings) base;
            inherit (made) legacyPackages;
            packages = flattenTree {
                default = python;
                "python-${pname}" = python;
                "xonsh-${pname}" = xonsh;
                "${pname}" = python;
                inherit python xonsh;
            };
            package = packages.default;
            defaultPackage = package;
            apps = mapAttrs (n: made.app) packages;
            app = apps.default;
            defaultApp = app;
            devShells = j.foldToSet [
                (mapAttrs (n: v: legacyPackages.mkShell { buildInputs = toList v; }) packages)
                { default = legacyPackages.mkShell { buildInputs = unique (attrValues packages); }; }
            ];
            devShell = devShells.default;
            defaultdevShell = devShell;
        };))
        overlayset
        { inherit pname callPackage; }
    ];
}
                '';
                default = python;
            };
            template = templates.default;
            defaultTemplate = template;
        };
        individual-outputs = with lib; j.foldToSet (flatten [
            overlayset
            nixosModules
            { inherit make lib channel registry profiles devices; }
        ]);
        make = system: overlays: with lib; rec {
            config' = rec {
                base = { inherit system; };
                default = base // { config = lib.j.attrs.configs.nixpkgs; };
                overlayed = default // { inherit overlays; };
            };
            nixpkgs' = {
                base = patch.nixpkgs.default inputs.nixpkgs config'.base;
                default = patch.nixpkgs.default inputs.nixpkgs config'.default;
                overlayed = patch.nixpkgs.default inputs.nixpkgs config'.overlayed;
            };
            pkgs' = {
                base = patch.pkgs.default inputs.nixpkgs config'.base;
                default = patch.pkgs.default inputs.nixpkgs config'.default;
                overlayed = patch.pkgs.default inputs.nixpkgs config'.overlayed;
            };
            pkgs = pkgs'.overlayed;
            legacyPackages = pkgs;
            nixpkgs = config'.overlayed;
            specialArgs = j.foldToSet [
                individual-outputs
                { inherit inputs legacyPackages pkgs nixpkgs; }
            ];
            app = drv: { type = "app"; program = "${drv}${drv.passthru.exePath or "/bin/${drv.meta.mainprogram or drv.executable or drv.pname or drv.name}"}"; };
            mkXonsh = pkglist: pname: let
                python3Packages = legacyPackages.Python3.pkgs;
            in (legacyPackages.xonsh.override { inherit python3Packages; }).overridePythonAttrs (old: {
                propagatedBuildInputs = j.filters.has.list [
                    pkglist
                    pname
                    (old.propagatedBuildInputs or [])
                ] python3Packages;
            });
            mkPython = python: pkglist: pname: python.withPackages (ppkgs: j.filters.has.list [
                pkglist
                pname
            ] ppkgs);
            withPackages = {
                python = j.foldToSet (flatten [
                    (map (python: (listToAttrs (map (pkg: nameValuePair "${python}-${pkg}" (pkglist: mkPython legacyPackages.${j.toCapital python} [
                        pkg
                        pkglist
                    ])) (attrNames overlayset.pythonOverlays.${python})))) [ "python" "python2" "python3" ])
                    (map (os: (listToAttrs (map (pkg: nameValuePair "xonsh-${pkg}" (pkglist: mkXonsh [ pkg pkglist ])) (attrNames overlayset.pythonOverlays.${os})))) [ "python3" "xonsh" ])
                    (listToAttrs (map (pkg: nameValuePair "xonsh-${pkg}" (pkglist: mkXonsh [ pkg pkglist ])) (attrNames overlayset.pythonOverlays.xonsh)))
                    (listToAttrs (map (python: nameValuePair python (pkglist: mkPython legacyPackages.${j.toCapital python} [
                        (attrNames overlayset.pythonOverlays.${python})
                        pkglist
                    ])) [ "python" "python2" "python3" ]))
                    { xonsh = pkglist: mkXonsh [ (attrNames overlayset.pythonOverlays.xonsh) pkglist ]; }
                ]);
            };
            buildInputs = with pkgs; [ git poetry2setup ];
        };
    in with lib; j.foldToSet [
        (eachSystem allSystems (system: let
            made = make system (attrValues overlayset.overlays);
        in rec {
            inherit (made) legacyPackages pkgs nixpkgs;
            packages = let
                pythonPackages = mapAttrs (n: v: v [] null) made.withPackages.python;
            in flattenTree (j.foldToSet [
                pythonPackages
                (j.filters.has.attrs [
                    (subtractLists (attrNames inputs.nixpkgs.legacyPackages.${system}) (attrNames legacyPackages))
                    (attrNames overlayset.overlays)
                ] legacyPackages)
                { default = pythonPackages.xonsh; }
            ]);
            package = packages.default;
            defaultPackage = package;
            apps = mapAttrs (n: made.app) packages;
            app = apps.default;
            defaultApp = app;
            devShells = j.foldToSet [
                (mapAttrs (n: v: pkgs.mkShell { buildInputs = toList v; }) packages)
                {
                    default = pkgs.mkShell { buildInputs = attrValues packages; };
                    site = pkgs.mkShell { buildInputs = with pkgs.nodePackages; [ uglifycss uglify-js pkgs.sd ]; };
                }
            ];
            devShell = devShells.default;
            defaultdevShell = devShell;
        }))
        individual-outputs
    ];
}