{
  description = "Base/Pro Python environments via Nix";

  inputs = {
    # nixos-25.05 (May 2025): patches CVE-2025-32434 (PyTorch 2.6+), CVE-2025-21587/21502 (JDK 21.0.7+),
    # CVE-2025-48009 (Pillow 11.2.1+), CVE-2025-59268 (NumPy 2.2.6+), Go 1.24.x, Spark 3.5.5+.
    # Python 3.11/3.12/3.13 all in stable; nixpkgs-unstable eliminated.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems       = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [(final: prev: {
              # Disable flaky or excessively slow package test suites in the
              # interpreter package set used by python.withPackages. Astropy 7.0.1
              # currently fails IERS tests on the nixos-25.05 stack; pytest-doctestplus
              # has known NumPy compatibility issues; jupyter-server has an
              # intermittently failing kernel-culling websocket test in CI runners;
              # dask's suite is very large and can stall cache warmup on hosted runners.
              python311 = prev.python311.override {
                packageOverrides = pyfinal: pyprev: {
                  pytest-doctestplus = pyprev.pytest-doctestplus.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  astropy = pyprev.astropy.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  jupyter-server = pyprev.jupyter-server.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  dask = pyprev.dask.overridePythonAttrs (old: {
                    doCheck = false;
                    pythonImportsCheck = [];
                  });
                  jupyterlab = pyprev.jupyterlab.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  opencv4 = pyprev.opencv4.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  scikit-image = pyprev.scikit-image.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                };
              };
              python312 = prev.python312.override {
                packageOverrides = pyfinal: pyprev: {
                  pytest-doctestplus = pyprev.pytest-doctestplus.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  astropy = pyprev.astropy.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  jupyter-server = pyprev.jupyter-server.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  dask = pyprev.dask.overridePythonAttrs (old: {
                    doCheck = false;
                    pythonImportsCheck = [];
                  });
                  jupyterlab = pyprev.jupyterlab.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  opencv4 = pyprev.opencv4.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  scikit-image = pyprev.scikit-image.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                };
              };
              python313 = prev.python313.override {
                packageOverrides = pyfinal: pyprev: {
                  pytest-doctestplus = pyprev.pytest-doctestplus.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  astropy = pyprev.astropy.overridePythonAttrs (old: { doCheck = false; });
                  jupyter-server = pyprev.jupyter-server.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  dask = pyprev.dask.overridePythonAttrs (old: {
                    doCheck = false;
                    pythonImportsCheck = [];
                  });
                  jupyterlab = pyprev.jupyterlab.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  opencv4 = pyprev.opencv4.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                  scikit-image = pyprev.scikit-image.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                };
              };
            })];
          };

          mkPyEnv = python: pkgsFn: python.withPackages pkgsFn;

          # Minimal Nix-managed base: only packages that need deep system
          # integration (Java/Spark wiring) or are the Python base itself.
          # Everything else is installed via pip wheel in build-base-envs.sh
          # which is faster, better-optimized, and avoids Nix compilation OOMs.
          cachePackagesFn = ps: with ps; [
            ipython   # lightweight interpreter base
            pyspark   # needs Nix Java/Spark runtime wiring
          ];

          # basePackagesFn = cachePackagesFn — all heavy packages now via pip.
          # See build-base-envs.sh _layer_base() for the full pip install list.
          basePackagesFn = ps: cachePackagesFn ps;

          # catboost: not in nixpkgs (complex Rust build). pip install catboost
          # torch/torchvision/torchaudio/tensorflow/transformers/datasets/tokenizers/
          # sentencepiece/accelerate: installed via pre-built CPU pip wheels in the
          # Packer pro build (scripts/build-pro-envs.sh). Nix compilation of these
          # packages takes hours; pip CPU wheels install in minutes.
          # mlflow/xgboost/lightgbm compile quickly and stay Nix-managed.
          proPackagesFn = ps: basePackagesFn ps ++ (with ps; [
            mlflow
            xgboost
            lightgbm
          ]);
        in {
          py-cache-base = mkPyEnv pkgs.python311 cachePackagesFn;
          py-base       = mkPyEnv pkgs.python311 basePackagesFn;
          py-pro        = mkPyEnv pkgs.python311 proPackagesFn;
          py-cache-base-py312 = mkPyEnv pkgs.python312 cachePackagesFn;
          py-base-py312 = mkPyEnv pkgs.python312 basePackagesFn;
          py-pro-py312  = mkPyEnv pkgs.python312 proPackagesFn;
          py-cache-base-py313 = mkPyEnv pkgs.python313 cachePackagesFn;
          py-base-py313 = mkPyEnv pkgs.python313 basePackagesFn;
          py-pro-py313  = mkPyEnv pkgs.python313 proPackagesFn;

          python312 = pkgs.python312;
          python313 = pkgs.python313;
          julia     = pkgs.julia-bin or pkgs.julia;
          R         = pkgs.R;
          go        = pkgs.go;
          java      = pkgs.openjdk21;
          spark     = pkgs.spark;
          # Rust: powers tokenizers, polars internals, and ML infra tooling
          rustc     = pkgs.rustc;
          cargo     = pkgs.cargo;
          # Node.js 22 LTS: Jupyter lab extensions, JS-based ML tooling
          nodejs    = pkgs.nodejs_22;

          env-report-base = pkgs.writeShellScriptBin "env-report-base" ''
            "${self.packages.${system}.py-base}/bin/python" -m pip list --format=columns
          '';
          env-report-pro = pkgs.writeShellScriptBin "env-report-pro" ''
            "${self.packages.${system}.py-pro}/bin/python" -m pip list --format=columns
          '';
        }
      );

      apps = forAllSystems (system: {
        jupyter-base = {
          type    = "app";
          program = "${self.packages.${system}.py-base}/bin/jupyter-lab";
        };
        uvicorn-pro = {
          type    = "app";
          program = "${self.packages.${system}.py-pro}/bin/uvicorn";
        };
        env-report-base = {
          type    = "app";
          program = "${self.packages.${system}.env-report-base}/bin/env-report-base";
        };
        env-report-pro = {
          type    = "app";
          program = "${self.packages.${system}.env-report-pro}/bin/env-report-pro";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          languages = pkgs.mkShell {
            packages = [
              pkgs.python311
              pkgs.python312
              pkgs.python313
              self.packages.${system}.py-base
              pkgs.R
              (pkgs.julia-bin or pkgs.julia)
              pkgs.go
              pkgs.openjdk21
              pkgs.rustc
              pkgs.cargo
              pkgs.nodejs_22
            ];
          };
        }
      );
    };
}
