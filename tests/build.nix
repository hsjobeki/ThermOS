# Eval tests: nix-build tests/build.nix
# One test:   nix-build tests/build.nix -A unitVerify
let
  thermos = import ../default.nix { };
  pkgs = thermos.pkgs;
  tree = thermos.tree;

  unitsDrv = (tree.modules.builders.modules.units { }).derivation;
  rootfsDrv = (tree.modules.builders.modules.rootfs { }).derivation;
  usersDrv = (tree.modules.builders.modules.users { }).derivation;
  etcDrv = (tree.modules.builders.modules.etc { }).derivation;
  imageDrv = (tree.modules.builders.modules.image { }).derivation;
  ukiDrv = (tree.modules.builders.modules.uki { }).derivation;
  # Regular-file stand-in for a UKI (vfat rejects symlinks, so it must be real).
  # Keeps this test independent of the uki builder.
  fakeUki = pkgs.writeText "fake-uki.efi" "MZ\n";
  imageWithEspDrv = (tree.modules.builders.modules.image { espUki = "${fakeUki}"; }).derivation;
  metal = import ../systems/metal.nix;
  types = thermos.types;

  # Stage-2 substrate: drive the kernel-modules builder with a synthetic
  # (system, force) + (system, available) publish, mirroring a real service.
  # The records reach the builder through a test publisher in a real tree
  kmTree = thermos.configure {
    modules.tests.modules.kmPublisher = import ./fixtures/kernel-modules-publisher.nix {
      inherit types;
    };
    options."/tests/kmPublisher".data = [
      {
        name = "loop";
        stage = "system";
        mode = "force";
      }
      {
        name = "dummy";
        stage = "system";
        mode = "available";
      }
    ];
  };
  kmResult = kmTree.modules.builders.modules."kernel-modules" { };
  kmClosure = kmResult.derivation;
  kmConf = (builtins.head kmResult.etc).text;
  kmPackagesEnv = pkgs.buildEnv {
    name = "thermos-km-test-env";
    paths = map (p: p.package) kmResult.packages;
  };
  kernelVersion = pkgs.linuxPackages.kernel.modDirVersion;
in
{
  # Structural INI validation (semantic verify needs /run/systemd/, see container tests)
  unitVerify = pkgs.runCommand "thermos-test-unit-verify" { } ''
    echo "unit INI structure"
    units=$(find ${unitsDrv}/etc/systemd/system -name '*.service' -o -name '*.timer' -o -name '*.socket' -o -name '*.mount' -o -name '*.target' 2>/dev/null)

    if [ -z "$units" ]; then
      echo "FAIL: no unit files found in ${unitsDrv}/etc/systemd/system"
      exit 1
    fi

    count=0
    for unit in $units; do
      name=$(basename "$unit")
      echo "  $name"

      sections=$(grep -c '^\[' "$unit")
      if [ "$sections" -eq 0 ]; then
        echo "FAIL: $name has no [Section] headers"
        exit 1
      fi

      case "$name" in
        *.service)
          grep -q '^\[Service\]' "$unit" || { echo "FAIL: $name missing [Service]"; exit 1; }
          ;;
      esac

      first_section_line=$(grep -n '^\[' "$unit" | head -1 | cut -d: -f1)
      if [ "$first_section_line" -gt 1 ]; then
        pre_section=$(head -n $((first_section_line - 1)) "$unit" | grep -c '^[A-Za-z].*=')
        if [ "$pre_section" -gt 0 ]; then
          echo "FAIL: $name has key=value lines before first section"
          exit 1
        fi
      fi

      bad_lines=$(grep -nvE '^(\[.*\]|[A-Za-z][A-Za-z0-9_]*=|#|;|$)' "$unit" || true)
      if [ -n "$bad_lines" ]; then
        echo "FAIL: $name has malformed lines:"
        echo "$bad_lines"
        exit 1
      fi

      count=$((count + 1))
    done

    echo "$count units ok"
    mkdir -p $out
    echo "$count units verified" > $out/result
  '';

  rootfsStructure = pkgs.runCommand "thermos-test-rootfs-structure" { } ''
    echo "rootfs structure"

    test -L ${rootfsDrv}/sbin/init || { echo "FAIL: /sbin/init missing"; exit 1; }
    target=$(readlink ${rootfsDrv}/sbin/init)
    echo "  /sbin/init -> $target"
    case "$target" in
      */systemd) ;;
      *) echo "FAIL: /sbin/init does not point to systemd"; exit 1 ;;
    esac

    test -e ${rootfsDrv}/etc/hostname || { echo "FAIL: /etc/hostname missing"; exit 1; }
    test -e ${rootfsDrv}/etc/os-release || { echo "FAIL: /etc/os-release missing"; exit 1; }

    units=$(find -L ${rootfsDrv}/etc/systemd/system -name '*.service' 2>/dev/null | head -1)
    test -n "$units" || { echo "FAIL: no service units in /etc/systemd/system"; exit 1; }

    test -d ${rootfsDrv}/etc/tmpfiles.d || test -L ${rootfsDrv}/etc/tmpfiles.d || { echo "FAIL: /etc/tmpfiles.d missing"; exit 1; }

    test -d ${rootfsDrv}/bin || test -L ${rootfsDrv}/bin || { echo "FAIL: /bin missing"; exit 1; }
    test -d ${rootfsDrv}/usr/bin || test -L ${rootfsDrv}/usr/bin || { echo "FAIL: /usr/bin missing"; exit 1; }

    test -e ${rootfsDrv}/bin/bash || { echo "FAIL: /bin/bash missing"; exit 1; }
    test -e ${rootfsDrv}/bin/systemctl || { echo "FAIL: /bin/systemctl missing"; exit 1; }
    test -e ${rootfsDrv}/bin/dbus-daemon || { echo "FAIL: /bin/dbus-daemon missing"; exit 1; }

    # dbus stock units
    test -e ${rootfsDrv}/etc/systemd/system/dbus.service || { echo "FAIL: dbus.service missing"; exit 1; }
    test -e ${rootfsDrv}/etc/systemd/system/dbus.socket || { echo "FAIL: dbus.socket missing"; exit 1; }
    test -d ${rootfsDrv}/etc/systemd/system/multi-user.target.wants || { echo "FAIL: multi-user.target.wants missing"; exit 1; }
    test -e ${rootfsDrv}/etc/systemd/system/multi-user.target.wants/dbus.service || { echo "FAIL: dbus.service not wanted by multi-user"; exit 1; }

    # dbus config
    test -e ${rootfsDrv}/etc/dbus-1/system.conf || { echo "FAIL: /etc/dbus-1/system.conf missing"; exit 1; }
    test -d ${rootfsDrv}/usr/share/dbus-1 || test -L ${rootfsDrv}/usr/share/dbus-1 || { echo "FAIL: /usr/share/dbus-1 missing"; exit 1; }

    for dir in proc sys dev run tmp; do
      test -d ${rootfsDrv}/$dir || { echo "FAIL: /$dir missing"; exit 1; }
    done

    test -d ${rootfsDrv}/nix/store || { echo "FAIL: /nix/store missing"; exit 1; }

    # Stage-2 kernel module dir: a symlink that must resolve. Empty closure by
    # default (no stage=system publisher in the base config).
    test -L ${rootfsDrv}/lib/modules || { echo "FAIL: /lib/modules not a symlink"; exit 1; }
    test -d ${rootfsDrv}/lib/modules || { echo "FAIL: /lib/modules does not resolve"; exit 1; }
    echo "  /lib/modules ok"

    echo "rootfs ok"
    mkdir -p $out
    echo "rootfs structure OK" > $out/result
  '';

  usersVerify = pkgs.runCommand "thermos-test-users-verify" { } ''
    echo "user/group format"
    count=0

    echo "  passwd"
    while IFS= read -r line; do
      fields=$(echo "$line" | awk -F: '{print NF}')
      if [ "$fields" -ne 7 ]; then
        echo "FAIL: passwd line has $fields fields (expected 7): $line"
        exit 1
      fi
      uid=$(echo "$line" | cut -d: -f3)
      gid=$(echo "$line" | cut -d: -f4)
      case "$uid" in *[!0-9]*) echo "FAIL: non-numeric uid: $line"; exit 1;; esac
      case "$gid" in *[!0-9]*) echo "FAIL: non-numeric gid: $line"; exit 1;; esac
      count=$((count + 1))
    done < ${usersDrv}/etc/passwd
    echo "  passwd: $count"

    echo "  group"
    gcount=0
    while IFS= read -r line; do
      fields=$(echo "$line" | awk -F: '{print NF}')
      if [ "$fields" -ne 4 ]; then
        echo "FAIL: group line has $fields fields (expected 4): $line"
        exit 1
      fi
      gid=$(echo "$line" | cut -d: -f3)
      case "$gid" in *[!0-9]*) echo "FAIL: non-numeric gid: $line"; exit 1;; esac
      gcount=$((gcount + 1))
    done < ${usersDrv}/etc/group

    echo "  shadow"
    scount=0
    while IFS= read -r line; do
      fields=$(echo "$line" | awk -F: '{print NF}')
      if [ "$fields" -ne 9 ]; then
        echo "FAIL: shadow line has $fields fields (expected 9): $line"
        exit 1
      fi
      scount=$((scount + 1))
    done < ${usersDrv}/etc/shadow

    grep -q '^root:' ${usersDrv}/etc/passwd || { echo "FAIL: root not in passwd"; exit 1; }

    root_uid=$(grep '^root:' ${usersDrv}/etc/passwd | cut -d: -f3)
    test "$root_uid" = "0" || { echo "FAIL: root uid is $root_uid, expected 0"; exit 1; }

    echo "users ok"
    mkdir -p $out
    echo "users verified" > $out/result
  '';

  etcContent = pkgs.runCommand "thermos-test-etc-content" { } ''
    echo "etc content"

    # No leading whitespace in hostname
    content=$(cat ${etcDrv}/etc/hostname)
    if [ "$content" != "thermos" ]; then
      echo "FAIL: /etc/hostname expected 'thermos', got '$content'"
      exit 1
    fi
    echo "  hostname ok"

    # os-release has correct key=value lines
    grep -q '^NAME=ThermOS' ${etcDrv}/etc/os-release || { echo "FAIL: os-release missing NAME=ThermOS"; exit 1; }
    grep -q '^ID=thermos' ${etcDrv}/etc/os-release || { echo "FAIL: os-release missing ID=thermos"; exit 1; }
    # No leading whitespace on any line
    if grep -qP '^\s+\S' ${etcDrv}/etc/os-release; then
      echo "FAIL: os-release has leading whitespace:"
      cat ${etcDrv}/etc/os-release
      exit 1
    fi
    echo "  os-release ok"

    # passwd lines have no leading whitespace
    if grep -qP '^\s' ${usersDrv}/etc/passwd; then
      echo "FAIL: passwd has leading whitespace:"
      cat ${usersDrv}/etc/passwd
      exit 1
    fi
    echo "  passwd ok"

    # unit files have no leading whitespace on section headers or key=value lines
    for unit in ${unitsDrv}/etc/systemd/system/*.service; do
      name=$(basename "$unit")
      if grep -qP '^\s+\[' "$unit"; then
        echo "FAIL: $name has indented section headers:"
        cat "$unit"
        exit 1
      fi
      if grep -qP '^\s+[A-Za-z].*=' "$unit"; then
        echo "FAIL: $name has indented key=value lines:"
        cat "$unit"
        exit 1
      fi
      echo "  $name ok"
    done

    echo "etc content ok"
    mkdir -p $out
    echo "content verified" > $out/result
  '';

  # Verify shells in passwd exist in rootfs, PATH entries exist
  shellPaths = pkgs.runCommand "thermos-test-shell-paths" { } ''
    echo "shell paths"
    # format: name:password:uid:gid:gecos:home:shell
    while IFS=: read -r name _ _ _ _ _ shell; do
      if [ ! -e "${rootfsDrv}$shell" ]; then
        echo "FAIL: $name shell $shell not in rootfs"
        exit 1
      fi
      echo "  $name -> $shell ok"
    done < ${usersDrv}/etc/passwd

    # PATH from /etc/profile: every dir must exist
    sed -n 's/.*PATH=//p' ${etcDrv}/etc/profile | tr ':' '\n' | while read -r d; do
      if [ ! -d "${rootfsDrv}$d" ]; then
        echo "FAIL: PATH entry $d not in rootfs"
        exit 1
      fi
      echo "  PATH $d ok"
    done

    echo "shell paths ok"
    mkdir -p $out
    echo "paths verified" > $out/result
  '';
  # Synthetic stage-2 build: the kernel-modules builder turns a (system, force)
  # + (system, available) publish into a depmod-resolvable /lib/modules closure,
  # a modules-load.d conf listing only force names, and kmod tooling.
  kernelModulesSubstrate = pkgs.runCommand "thermos-test-kernel-modules" { } ''
    echo "kernel-modules substrate"

    ver=$(ls ${kmClosure}/lib/modules)
    echo "  version: $ver"
    if [ "$ver" != "${kernelVersion}" ]; then
      echo "FAIL: closure version $ver != kernel ${kernelVersion}"
      exit 1
    fi

    test -f ${kmClosure}/lib/modules/$ver/modules.dep || { echo "FAIL: modules.dep missing"; exit 1; }

    # force module present in the tree
    find ${kmClosure}/lib/modules -name 'loop.ko*' | grep -q . || { echo "FAIL: loop.ko missing"; exit 1; }
    echo "  loop.ko ok"

    # available module present in the tree for udev modalias autoload
    find ${kmClosure}/lib/modules -name 'dummy.ko*' | grep -q . || { echo "FAIL: dummy.ko missing"; exit 1; }
    echo "  dummy.ko ok"

    # modules-load.d lists the force module only; available is autoloaded by udev
    conf=${pkgs.writeText "thermos-test-modules-load" kmConf}
    grep -qx 'loop' "$conf" || { echo "FAIL: modules-load.d missing loop"; cat "$conf"; exit 1; }
    if grep -qx 'dummy' "$conf"; then echo "FAIL: available module dummy must not be force-loaded"; exit 1; fi
    echo "  modules-load.d ok"

    # kmod tooling shipped alongside the substrate
    test -e ${kmPackagesEnv}/bin/modprobe || { echo "FAIL: modprobe missing from packages"; exit 1; }
    echo "  modprobe ok"

    echo "substrate ok"
    mkdir -p $out
    echo "kernel-modules substrate verified" > $out/result
  '';

  # Unit under test: /builders/image GPT layout
  # produced by systemd-repart
  # Assertion: partition table shape from the raw image
  imagePartStructure =
    pkgs.runCommand "thermos-test-image-structure" { nativeBuildInputs = [ pkgs.util-linux ]; }
      ''
        echo "image gpt"
        img=${imageDrv}/thermos.raw
        test -f "$img" || { echo "FAIL: thermos.raw missing"; exit 1; }
        test -f ${imageDrv}/repart-output.json || { echo "FAIL: repart-output.json missing"; exit 1; }

        dump=$(sfdisk -d "$img")
        echo "$dump"

        echo "$dump" | grep -q '^label: gpt' || { echo "FAIL: not a GPT table"; exit 1; }

        parts=$(echo "$dump" | grep -c 'type=')
        if [ "$parts" -ne 2 ]; then echo "FAIL: expected 2 partitions, got $parts"; exit 1; fi

        # ESP type GUID: SD_GPT_ESP; UEFI spec. repart resolves Type=esp to this.
        # See: https://github.com/uapi-group/specifications/blob/main/specs/discoverable_partitions_specification.md
        echo "$dump" | grep -qi 'type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B' || { echo "FAIL: ESP partition missing"; exit 1; }
        echo "  esp ok"

        # Root type GUID: SD_GPT_ROOT_X86_64; UAPI Discoverable Partitions Spec
        # See: https://github.com/uapi-group/specifications/blob/main/specs/discoverable_partitions_specification.md
        rootline=$(echo "$dump" | grep -i 'type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709')
        test -n "$rootline" || { echo "FAIL: root partition missing"; exit 1; }
        echo "$rootline" | grep -qi 'uuid=44444444-4444-4444-8888-888888888888' || { echo "FAIL: root PARTUUID mismatch: $rootline"; exit 1; }
        echo "  root ok"

        echo "image gpt ok"
        mkdir -p $out
        echo "image structure verified" > $out/result
      '';

  # Unit under test: /builders/uki. Bundles kernel+initrd+cmdline+os-release into
  # a UKI PE binary via systemd-stub + ukify. Asserts it is an EFI application and
  # carries the four payload sections (no boot needed; pure binary inspection).
  ukiStructure =
    pkgs.runCommand "thermos-test-uki-structure"
      {
        nativeBuildInputs = [
          pkgs.file
          pkgs.binutils
        ];
      }
      ''
        uki=${ukiDrv}/thermos.efi
        test -f "$uki" || { echo "FAIL: thermos.efi missing"; exit 1; }

        file "$uki" | grep -qE 'PE32\+.*(EFI application|executable)' || {
          echo "FAIL: not a PE32+ EFI application:"; file "$uki"; exit 1; }
        echo "  efi binary ok"

        # systemd-stub payload sections, by name (objdump column 2).
        secs=$(objdump -h "$uki" | awk '{print $2}')
        for s in .linux .initrd .cmdline .osrel; do
          echo "$secs" | grep -qxF "$s" || { echo "FAIL: missing UKI section $s"; objdump -h "$uki"; exit 1; }
          echo "  section $s ok"
        done

        echo "uki ok"
        mkdir -p $out
        echo "uki structure verified" > $out/result
      '';

  # Unit under test: /builders/image espUki option. Asserts a supplied EFI binary
  # lands at the firmware fallback path EFI/BOOT/BOOTX64.EFI on the ESP, read back
  # from the vfat partition without a loop mount (mtools at the ESP byte offset).
  espPopulated =
    pkgs.runCommand "thermos-test-esp-populated"
      {
        nativeBuildInputs = [
          pkgs.util-linux
          pkgs.mtools
        ];
      }
      ''
        img=${imageWithEspDrv}/thermos.raw
        # ESP start sector from the C12A7328 (ESP) line; sectors are 512 bytes.
        start=$(sfdisk -d "$img" | sed -n 's/.*start=[[:space:]]*\([0-9]*\).*type=C12A7328.*/\1/p')
        test -n "$start" || { echo "FAIL: no ESP partition found"; sfdisk -d "$img"; exit 1; }
        offset=$((start * 512))
        echo "  esp offset: $offset"

        mdir -i "$img@@$offset" ::/EFI/BOOT | grep -qi 'BOOTX64' || {
          echo "FAIL: EFI/BOOT/BOOTX64.EFI missing from ESP"
          mdir -i "$img@@$offset" ::/EFI/BOOT 2>&1 || true
          exit 1
        }
        echo "  bootx64.efi present"

        echo "esp populated ok"
        mkdir -p $out
        echo "esp population verified" > $out/result
      '';

  # Unit under test: systems/metal.nix composition. Proves the metal image's ESP
  # carries the metal UKI and that UKI's baked cmdline boots root by PARTUUID
  # Chain: rootPartUUID -> cmdline -> uki -> espUki
  metalImage =
    pkgs.runCommand "thermos-test-metal-image"
      {
        nativeBuildInputs = [
          pkgs.util-linux
          pkgs.mtools
          pkgs.binutils
          pkgs.diffutils
        ];
      }
      ''
        img=${metal.image}/thermos.raw
        start=$(sfdisk -d "$img" | sed -n 's/.*start=[[:space:]]*\([0-9]*\).*type=C12A7328.*/\1/p')
        test -n "$start" || { echo "FAIL: no ESP partition found"; sfdisk -d "$img"; exit 1; }
        offset=$((start * 512))

        mcopy -i "$img@@$offset" ::/EFI/BOOT/BOOTX64.EFI out.efi || {
          echo "FAIL: could not read EFI/BOOT/BOOTX64.EFI from ESP"; exit 1; }

        # The binary on the ESP is exactly the metal UKI.
        cmp out.efi ${metal.uki}/thermos.efi || {
          echo "FAIL: ESP BOOTX64.EFI is not the metal UKI"; exit 1; }
        echo "  esp carries metal uki"

        # The baked cmdline boots root by the fixed PARTUUID.
        objcopy -O binary --only-section=.cmdline out.efi cmdline.bin
        grep -aq 'root=PARTUUID=44444444-4444-4444-8888-888888888888' cmdline.bin || {
          echo "FAIL: UKI cmdline missing root=PARTUUID="; cat cmdline.bin; echo; exit 1; }
        echo "  cmdline root=PARTUUID ok"

        echo "metal image ok"
        mkdir -p $out
        echo "metal image verified" > $out/result
      '';
}
