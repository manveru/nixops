{ nixopsSrc ? { outPath = ./.; revCount = 0; shortRev = "abcdef"; rev = "HEAD"; }
, officialRelease ? false
}:

let

  pkgs = import <nixpkgs> { };

  version = "1.3" + (if officialRelease then "" else "pre${toString nixopsSrc.revCount}_${nixopsSrc.shortRev}");

  # Use this until the patches are upstreamed.
  # Warning: will be rebased at will
  libcloud = pkgs.lib.overrideDerivation pkgs.pythonPackages.libcloud ( args: {
    src = pkgs.fetchgit {
      url = https://github.com/Phreedom/libcloud.git;
      rev = "cc70ff7f83e39d5048639f0e1a8f3966b3132ab1";
      sha256 = "33b654fb42794a8d4ad5982bfa45b6c4c9c6a018a16e591a11ee308cd0160567";
    };

    preConfigure = "cp libcloud/test/secrets.py-dist libcloud/test/secrets.py";
  });

in

rec {

  tarball = pkgs.releaseTools.sourceTarball {
    name = "nixops-tarball";

    src = nixopsSrc;

    inherit version;

    officialRelease = true; # hack

    buildInputs = [ pkgs.git pkgs.libxslt ];

    postUnpack = ''
      # Clean up when building from a working tree.
      (cd $sourceRoot && (git ls-files -o | xargs -r rm -v))
    '';

    distPhase =
      ''
        # Generate the manual and the man page.
        cp ${import ./doc/manual { revision = nixopsSrc.rev; }} doc/manual/machine-options.xml
        ${pkgs.lib.concatMapStrings (fn: ''
          cp ${import ./doc/manual/resource.nix { revision = nixopsSrc.rev; module = ./nix + ("/" + fn + ".nix"); }} doc/manual/${fn}-options.xml
        '') [ "sqs-queue" "ec2-keypair" "s3-bucket" "iam-role" "ssh-keypair" "ec2-security-group" "elastic-ip"
              "gce-disk" "gce-image" "gce-forwarding-rule" "gce-http-health-check" "gce-network"
              "gce-static-ip" "gce-target-pool" "gse-bucket" ]}

        make -C doc/manual install docbookxsl=${pkgs.docbook5_xsl}/xml/xsl/docbook \
            docdir=$out/manual mandir=$TMPDIR/man

        substituteInPlace scripts/nixops --subst-var-by version ${version}
        substituteInPlace setup.py --subst-var-by version ${version}

        releaseName=nixops-$VERSION
        mkdir ../$releaseName
        cp -prd . ../$releaseName
        rm -rf ../$releaseName/.git
        mkdir $out/tarballs
        tar  cvfj $out/tarballs/$releaseName.tar.bz2 -C .. $releaseName

        echo "doc manual $out/manual manual.html" >> $out/nix-support/hydra-build-products
      '';
  };

  build = pkgs.lib.genAttrs [ "x86_64-linux" "i686-linux" "x86_64-darwin" ] (system:
    with import <nixpkgs> { inherit system; };

    pythonPackages.buildPythonPackage rec {
      name = "nixops-${version}";
      namePrefix = "";

      src = "${tarball}/tarballs/*.tar.bz2";

      buildInputs = [ pythonPackages.nose pythonPackages.coverage ];

      propagatedBuildInputs =
        [ pythonPackages.prettytable
          pythonPackages.boto
          pythonPackages.hetzner
          libcloud
          pythonPackages.sqlite3
        ];

      # For "nix-build --run-env".
      shellHook = ''
        export PYTHONPATH=$(pwd):$PYTHONPATH
        export PATH=$(pwd)/scripts:$PATH
        export SSL_CERT_FILE=$OPENSSL_X509_CERT_FILE
      '';

      doCheck = true;

      postInstall =
        ''
          # Backward compatibility symlink.
          ln -s nixops $out/bin/charon

          make -C doc/manual install \
            docdir=$out/share/doc/nixops mandir=$out/share/man

          mkdir -p $out/share/nix/nixops
          cp -av nix/* $out/share/nix/nixops

          # Add openssh to nixops' PATH. On some platforms, e.g. CentOS and RHEL
          # the version of openssh is causing errors when have big networks (40+)
          wrapProgram $out/bin/nixops --prefix PATH : "${openssh}/bin" --set SSL_CERT_FILE "\$OPENSSL_X509_CERT_FILE"
        ''; # */

      meta.description = "Nix package for ${stdenv.system}";
    });

  # This is included here, so it's easier to fetch by the newly installed
  # Hetzner machine directly instead of waiting for ages if you have a
  # connection with slow upload speed.
  hetznerBootstrap = import ./nix/hetzner-bootstrap.nix;

  tests.none_backend = (import ./tests/none-backend.nix {
    nixops = build.x86_64-linux;
    system = "x86_64-linux";
  }).test;

  tests.hetzner_backend = (import ./tests/hetzner-backend.nix {
    nixops = build.x86_64-linux;
    system = "x86_64-linux";
  }).test;
}
