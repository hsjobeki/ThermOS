# Eval tests: nix-build tests/build.nix
# One test:   nix-build tests/build.nix -A unitVerify
let
  thermos = (import ../default.nix) { };
  pkgs = thermos.pkgs;
  ev = thermos.evaluated;

  unitsDrv = (ev.modules.builders.modules.units { }).derivation;
  rootfsDrv = thermos.rootfs;
  usersDrv = (ev.modules.builders.modules.users { }).derivation;
  etcDrv = (ev.modules.builders.modules.etc { }).derivation;
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

    for dir in proc sys dev run tmp; do
      test -d ${rootfsDrv}/$dir || { echo "FAIL: /$dir missing"; exit 1; }
    done

    test -d ${rootfsDrv}/nix/store || { echo "FAIL: /nix/store missing"; exit 1; }

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
}
