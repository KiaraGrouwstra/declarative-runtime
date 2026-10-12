# jkossis/garage Terraform/OpenTofu provider, built from source.
#
# Not packaged in the pinned nixpkgs, so we vendor it here using the nixpkgs
# `terraform-providers.mkProvider` builder, same as ../forgejo/pkg.nix. Garage's
# own project publishes no provider; this one targets Garage's v2 admin API.
#
# To update: bump `rev`, then refresh `hash` (source) and `vendorHash` (Go
# module set) together.
{ pkgs }:
pkgs.terraform-providers.mkProvider {
  owner = "jkossis";
  repo = "terraform-provider-garage";
  rev = "v1.0.5";
  spdx = "MPL-2.0";
  hash = "sha256-j9rf8ynqPl0JTv/K5ouVBitH41lIRnDiMvulx7OarZE=";
  vendorHash = "sha256-r6WqUIatjVjvC98PlbVPm3w1/XZPhdYriG4KsoqrkgY=";
  homepage = "https://registry.terraform.io/providers/jkossis/garage";
}
