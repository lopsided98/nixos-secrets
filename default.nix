{ lib, nixShell ? false, buildPythonApplication, mypy, python-gnupg }:

buildPythonApplication {
  name = "nixos-secrets";

  # lib.inNixShell can't be used here because it will return a false positive
  # if this package is pulled into a shell
  src = if nixShell then null else lib.cleanSource ./.;

  nativeBuildInputs = [ mypy ];
  propagatedBuildInputs = [ python-gnupg ];

  meta = with lib; {
    description = "Encrypted secrets management for NixOS";
    homepage = "https://github.com/lopsided98/nixos-secrets";
    license = licenses.mit;
    maintainers = with maintainers; [ lopsided98 ];
  };
}
