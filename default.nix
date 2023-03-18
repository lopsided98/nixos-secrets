{ lib, nixShell ? false, buildPythonApplication, mypy, black, flake8, rope
, python-gnupg }:

buildPythonApplication {
  name = "nixos-secrets";

  # lib.inNixShell can't be used here because it will return a false positive
  # if this package is pulled into a shell
  src = if nixShell then null else lib.cleanSourceWith {
    filter = name: type: let baseName = baseNameOf (toString name); in !(
      # Filter out PyCharm project folder
      (baseName == ".idea" && type == "directory") ||
      # Filter out mypy cache
      (baseName == ".mypy_cache" && type == "directory")
    );
    src = lib.cleanSource ./.;
  };

  nativeBuildInputs = [
    mypy
  ] ++ lib.optionals nixShell [
    black
    flake8
    rope
  ];
  propagatedBuildInputs = [ python-gnupg ];

  meta = with lib; {
    description = "Encrypted secrets management for NixOS";
    homepage = "https://github.com/lopsided98/nixos-secrets";
    license = licenses.mit;
    maintainers = with maintainers; [ lopsided98 ];
  };
}
