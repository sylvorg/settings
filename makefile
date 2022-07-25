.RECIPEPREFIX := |
.DEFAULT_GOAL := tangle

define nixShell
nix-shell -E '(import $(realfileDir)).devShells.$${builtins.currentSystem}.makeshell-$1' --show-trace --run
endef

mkfilePath := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfileDir := $(dir $(mkfilePath))
realfileDir := $(realpath $(mkfileDir))
type := $(subst ",,$(shell nix eval --impure --expr '(import $(realfileDir)).type' || echo general))
projectName := $(subst ",,$(shell nix eval --impure --expr '(import $(realfileDir)).pname' || basename $(mkfileDir)))
tangleTask := make -nf $(mkfilePath) test && echo test || echo tangle
files := $(mkfileDir)/nix.org $(mkfileDir)/flake.org $(mkfileDir)/tests.org $(mkfileDir)/README.org $(mkfileDir)/$(projectName)

add:
|git -C $(mkfileDir) add .

commit: add
|git -C $(mkfileDir) commit --allow-empty-message -am ""

push: commit
|git -C $(mkfileDir) push

update-%: updateInput := nix flake lock $(realfileDir) --update-input
update-%:
|$(eval input := $(shell echo $@ | cut -d "-" -f2-))
ifeq ($(input), settings)
|$(updateInput) $(input) || :
else ifeq ($(input), all)
|nix flake update $(realfileDir)
else
|$(updateInput) $(input)
endif

tangle: update-settings
|$(call nixShell,general) "org-tangle -f $(files)"

tangle-%: update-settings
|$(call nixShell,general) "org-tangle -f $(mkfileDir)/$(shell echo $@ | cut -d "-" -f2-).org"

update:
ifeq ($(projectName), settings)
|$(shell nix eval --impure --expr 'with (import $(realfileDir)); with pkgs.$${builtins.currentSystem}.lib; "nix flake lock $(realfileDir) --update-input $${concatStringsSep " --update-input " (filter (input: ! ((elem input [ "nixos-master" "nixos-unstable" ]) || (hasSuffix "-small" input))) (attrNames inputs))}"' | tr -d '"')
else
|nix flake update $(realfileDir)
endif

quick: tangle push

super: update push

super-%: update-% push ;
