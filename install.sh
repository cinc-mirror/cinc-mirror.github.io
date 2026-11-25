#!/bin/sh
# WARNING: REQUIRES /bin/sh
#
# - must run on /bin/sh on solaris 9
# - must run on /bin/sh on AIX 6.x
#
# Copyright:: Copyright (c) 2010-2018 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# helpers.sh
############
# This section has some helper functions to make life easier.
#
# Outputs:
# $tmp_dir: secure-ish temp directory that can be used during installation.
############

# Check whether a command exists - returns 0 if it does, 1 if it does not
exists() {
  if command -v "$1" >/dev/null 2>&1
  then
    return 0
  else
    return 1
  fi
}

# Output the instructions to report bug about this script
report_bug() {
  echo "Version: $version"
  echo ""
  echo "Please file a Bug Report at https://gitlab.com/cinc-project/distribution/mixlib-install/-/issues"
  echo "Alternatively, feel free to open a Support Ticket at https://gitlab.com/groups/cinc-project/-/issues"
  echo "More Cinc support resources can be found at https://www.cinc.sh/support"
  echo ""
  echo "Please include as many details about the problem as possible i.e., how to reproduce"
  echo "the problem (if possible), type of the Operating System and its version, etc.,"
  echo "and any other relevant details that might help us with troubleshooting."
  echo ""
}

checksum_mismatch() {
  echo "Package checksum mismatch!"
  report_bug
  exit 1
}

unable_to_retrieve_package() {
  echo "Unable to retrieve a valid package!"
  report_bug
  echo "Metadata URL: $metadata_url"
  if [ -n "$download_url" ]; then
    echo "Download URL: $download_url"
  fi
  if [ -n "$stderr_results" ]; then
    printf '\nDEBUG OUTPUT FOLLOWS:\n%s\n' "$stderr_results"
  fi
  exit 1
}

http_404_error() {
  echo "Omnitruck artifact does not exist for version $version on platform $platform"
  echo ""
  echo "Either this means:"
  echo "   - We do not support $platform"
  echo "   - We do not have an artifact for $version"
  echo ""
  echo "This is often the latter case due to running a prerelease or RC version of Cinc"
  echo "or a gem version which was only pushed to rubygems and not omnitruck."
  echo ""
  echo "You may be able to set your knife[:bootstrap_version] to the most recent stable"
  echo "release of Cinc to fix this problem (or the most recent stable major version number)."
  echo ""
  echo "In order to test the version parameter, adventurous users may take the Metadata URL"
  echo "below and modify the '&v=<number>' parameter until you successfully get a URL that"
  echo "does not 404 (e.g. via curl or wget).  You should be able to use '&v=11' or '&v=12'"
  echo "successfully."
  echo ""
  echo "If you cannot fix this problem by setting the bootstrap_version, it probably means"
  echo "that $platform is not supported."
  echo ""
  # deliberately do not call report_bug to suppress bug report noise.
  echo "Metadata URL: $metadata_url"
  if [ -n "$download_url" ]; then
    echo "Download URL: $download_url"
  fi
  if [ -n "$stderr_results" ]; then
    printf '\nDEBUG OUTPUT FOLLOWS:\n%s\n' "$stderr_results"
  fi
  exit 1
}

capture_tmp_stderr() {
  # spool up /tmp/stderr from all the commands we called
  if [ -f "$tmp_dir/stderr" ]; then
    output=`cat "$tmp_dir"/stderr`
    stderr_results="${stderr_results}\nSTDERR from $1:\n\n$output\n"
    rm "$tmp_dir"/stderr
  fi
}

# do_wget URL FILENAME
do_wget() {
  echo "trying wget..."
  # If filename is empty, use --content-disposition to get filename from server
  if [ -z "$2" ]; then
    wget --user-agent="User-Agent: mixlib-install/4.1.2" --content-disposition "$1" 2>"$tmp_dir"/stderr
  else
    wget --user-agent="User-Agent: mixlib-install/4.1.2" -O "$2" "$1" 2>"$tmp_dir"/stderr
  fi
  rc=$?
  # check for 404
  if grep "ERROR 404" "$tmp_dir"/stderr >/dev/null 2>&1; then
    echo "ERROR 404"
    http_404_error
  fi

  # check for bad return status (skip empty output check if using content-disposition)
  if [ $rc -ne 0 ]; then
    capture_tmp_stderr "wget"
    return 1
  fi

  # Only check for empty output if we specified a filename
  if [ -n "$2" ] && [ ! -s "$2" ]; then
    capture_tmp_stderr "wget"
    return 1
  fi

  return 0
}

# do_curl URL FILENAME
do_curl() {
  echo "trying curl..."
  # If filename is empty, use -O and -J to get filename from Content-Disposition header
  if [ -z "$2" ]; then
    curl -A "User-Agent: mixlib-install/4.1.2" --retry 5 -sL --fail -D "$tmp_dir"/stderr -O -J "$1"
    rc=$?
  else
    curl -A "User-Agent: mixlib-install/4.1.2" --retry 5 -sL --fail -D "$tmp_dir"/stderr "$1" > "$2"
    rc=$?
  fi

  # check for 404 (matches both HTTP/1.1 "404 Not Found" and HTTP/2 "404")
  if grep "404" "$tmp_dir"/stderr >/dev/null 2>&1; then
    echo "ERROR 404"
    http_404_error
  fi

  # check for bad return status
  if [ $rc -ne 0 ]; then
    capture_tmp_stderr "curl"
    return 1
  fi

  # Only check for empty output if we specified a filename
  if [ -n "$2" ] && [ ! -s "$2" ]; then
    capture_tmp_stderr "curl"
    return 1
  fi

  return 0
}

# do_fetch URL FILENAME
do_fetch() {
  echo "trying fetch..."
  fetch --user-agent="User-Agent: mixlib-install/4.1.2" -o "$2" "$1" 2>"$tmp_dir"/stderr
  # check for bad return status
  [ $? -ne 0 ] && return 1
  return 0
}

# do_perl URL FILENAME
do_perl() {
  echo "trying perl..."
  perl -e 'use LWP::Simple; getprint($ARGV[0]);' "$1" > "$2" 2>"$tmp_dir"/stderr
  rc=$?
  # check for HTTP error status codes (4xx/5xx)
  if grep "^[45][0-9][0-9] " "$tmp_dir"/stderr >/dev/null 2>&1; then
    if grep "404 Not Found" "$tmp_dir"/stderr >/dev/null 2>&1; then
      echo "ERROR 404"
      http_404_error
    fi
    capture_tmp_stderr "perl"
    return 1
  fi

  # check for bad return status or empty output
  if [ $rc -ne 0 ] || [ ! -s "$2" ]; then
    capture_tmp_stderr "perl"
    return 1
  fi

  return 0
}

# do_python URL FILENAME
do_python() {
  echo "trying python..."
  python -c "import sys,urllib2; sys.stdout.write(urllib2.urlopen(urllib2.Request(sys.argv[1], headers={ 'User-Agent': 'mixlib-install/4.1.2' })).read())" "$1" > "$2" 2>"$tmp_dir"/stderr
  rc=$?
  # check for 404
  if grep "HTTP Error 404" "$tmp_dir"/stderr >/dev/null 2>&1; then
    echo "ERROR 404"
    http_404_error
  fi

  # check for bad return status or empty output
  if [ $rc -ne 0 ] || [ ! -s "$2" ]; then
    capture_tmp_stderr "python"
    return 1
  fi
  return 0
}

# returns 0 if checksums match
do_checksum() {
  if exists sha256sum; then
    echo "Comparing checksum with sha256sum..."
    checksum=`sha256sum "$1" | awk '{ print $1 }'`
    [ "$checksum" = "$2" ]
    return $?
  elif exists shasum; then
    echo "Comparing checksum with shasum..."
    checksum=`shasum -a 256 "$1" | awk '{ print $1 }'`
    [ "$checksum" = "$2" ]
    return $?
  else
    echo "WARNING: could not find a valid checksum program, pre-install shasum or sha256sum in your O/S image to get validation..."
    return 0
  fi
}

# do_download URL FILENAME
do_download() {
  echo "downloading $1"
  echo "  to file $2"

  url="$1"
  if [ "$platform" = "solaris2" ]; then
    if [ "$platform_version" = "5.9" ] || [ "$platform_version" = "5.10" ]; then
      # solaris 9 lacks openssl, solaris 10 lacks recent enough credentials - your base O/S is completely insecure, please upgrade
      url=`echo "$url" | sed -e 's/https/http/'`
    fi
  fi

  # we try all of these until we get success.
  # perl, in particular may be present but LWP::Simple may not be installed

  if exists wget; then
    do_wget "$url" "$2" && return 0
  fi

  if exists curl; then
    do_curl "$url" "$2" && return 0
  fi

  if exists fetch; then
    do_fetch "$url" "$2" && return 0
  fi

  if exists perl; then
    do_perl "$url" "$2" && return 0
  fi

  if exists python; then
    do_python "$url" "$2" && return 0
  fi

  unable_to_retrieve_package
}

# install_file TYPE FILENAME
# TYPE is "rpm", "deb", "solaris", "sh", etc.
install_file() {
  echo "Installing $project $version"
  case "$1" in
    "rpm")
      if [ "$platform" = "nexus" ] || [ "$platform" = "ios_xr" ]; then
        echo "installing with yum..."
        yum install -yv "$2"
      else
        echo "installing with rpm..."
        rpm -Uvh --oldpackage --replacepkgs "$2"
      fi
      ;;
    "deb")
      echo "installing with dpkg..."
      dpkg -i "$2"
      ;;
    "bff")
      echo "installing with installp..."
      installp -aXYgd "$2" all
      ;;
    "solaris")
      echo "installing with pkgadd..."
      echo "conflict=nocheck" > "$tmp_dir"/nocheck
      echo "action=nocheck" >> "$tmp_dir"/nocheck
      echo "mail=" >> "$tmp_dir"/nocheck
      pkgrm -a "$tmp_dir"/nocheck -n "$project" >/dev/null 2>&1 || true
      pkgadd -G -n -d "$2" -a "$tmp_dir"/nocheck "$project"
      ;;
    "pkg")
      echo "installing with installer..."
      cd / && /usr/sbin/installer -pkg "$2" -target /
      ;;
    "dmg")
      echo "installing dmg file..."
      hdiutil detach "/Volumes/cinc_project" >/dev/null 2>&1 || true
      hdiutil attach "$2" -mountpoint "/Volumes/cinc_project"
      cd / && /usr/sbin/installer -pkg "`find "/Volumes/cinc_project" -name \*.pkg`" -target /
      hdiutil detach "/Volumes/cinc_project"
      ;;
    "sh" )
      echo "installing with sh..."
      sh "$2"
      ;;
    "p5p" )
      echo "installing p5p package..."
      pkg install -g "$2" "$project"
      ;;
    *)
      echo "Unknown filetype: $1"
      report_bug
      exit 1
      ;;
  esac
  if [ $? -ne 0 ]; then
    echo "Installation failed"
    report_bug
    exit 1
  fi
}

if [ -z "$TMPDIR" ]; then
  tmp="/tmp"
else
  tmp=$TMPDIR
fi
# secure-ish temp dir creation without having mktemp available (DDoS-able but not exploitable)
tmp_dir="$tmp/install.sh.$$"
(umask 077 && mkdir "$tmp_dir") || exit 1

############
# end of helpers.sh
############


# script_cli_parameters.sh
############
# This section reads the CLI parameters for the install script and translates
#   them to the local parameters to be used later by the script.
#
# Outputs:
# $version: Requested version to be installed.
# $channel: Channel to install the product from
# $project: Project to be installed
# $cmdline_filename: Name of the package downloaded on local disk.
# $cmdline_dl_dir: Name of the directory downloaded package will be saved to on local disk.
# $install_strategy: Method of package installations. default strategy is to always install upon exec. Set to "once" to skip if project is installed
# $download_url_override: Install package downloaded from a direct URL.
# $checksum: SHA256 for download_url_override file (optional)
############

# Defaults
channel="stable"
project="cinc"

while getopts pnv:b:c:f:P:d:s:l:a: opt
do
  case "$opt" in

    v)  version="$OPTARG";;
    b)  base_api_url="$OPTARG";;
    c)  channel="$OPTARG";;
    p)  channel="current";; # compat for prerelease option
    n)  channel="current";; # compat for nightlies option
    f)  cmdline_filename="$OPTARG";;
    P)  project="$OPTARG";;
    d)  cmdline_dl_dir="$OPTARG";;
    s)  install_strategy="$OPTARG";;
    l)  download_url_override="$OPTARG";;
    a)  checksum="$OPTARG";;
    \?)   # unknown flag
      echo >&2 \
      "usage: $0 [-P project] [-b base_api_url] [-c release_channel] [-v version] [-f filename | -d download_dir] [-s install_strategy] [-l download_url_override] [-a checksum]"
      exit 1;;
  esac
done

shift "`expr $OPTIND - 1`"


# Check for product installation in various locations
install_paths="/opt/$project/bin"

for path in $install_paths; do
  if [ -d "$path" ] && [ "$install_strategy" = "once" ]; then
    echo "$project installation detected at $path"
    echo "install_strategy set to 'once'"
    echo "Nothing to install"
    exit
  fi
done


# platform_detection.sh
############
# This section makes platform detection compatible with omnitruck on the system
#   it runs.
#
# Outputs:
# $platform: Name of the platform.
# $platform_version: Version of the platform.
# $machine: System's architecture.
############

#
# Platform and Platform Version detection
#
# NOTE: This logic should match ohai platform and platform_version matching.
# do not invent new platform and platform_version schemas, just make this behave
# like what ohai returns as platform and platform_version for the system.
#
# ALSO NOTE: Do not mangle platform or platform_version here.  It is less error
# prone and more future-proof to do that in the server, and then all omnitruck clients
# will 'inherit' the changes (install.sh is not the only client of the omnitruck
# endpoint out there).
#

machine=`uname -m`
os=`uname -s`

if [ -f "/etc/lsb-release" ] && grep DISTRIB_ID /etc/lsb-release >/dev/null && ! grep wrlinux /etc/lsb-release >/dev/null; then
  platform=`grep DISTRIB_ID /etc/lsb-release | cut -d "=" -f 2 | tr 'A-Z' 'a-z'`
  platform_version=`grep DISTRIB_RELEASE /etc/lsb-release | cut -d "=" -f 2`

  if [ "$platform" = '"cumulus linux"' ]; then
    platform="cumulus_linux"
  elif [ "$platform" = '"cumulus networks"' ]; then
    platform="cumulus_networks"
  fi

elif [ -f "/etc/debian_version" ]; then
  platform="debian"
  platform_version=`cat /etc/debian_version`
elif [ -f "/etc/Eos-release" ]; then
  # EOS may also contain /etc/redhat-release so this check must come first.
  platform=arista_eos
  platform_version=`awk '{print $4}' /etc/Eos-release`
  machine="i386"
elif [ -f "/etc/redhat-release" ]; then
  platform=`sed 's/^\(.\+\) release.*/\1/' /etc/redhat-release | tr 'A-Z' 'a-z'`
  platform_version=`sed 's/^.\+ release \([.0-9]\+\).*/\1/' /etc/redhat-release`

  if [ "$platform" = "rocky linux" ]; then
    . /etc/os-release
 	os="${REDHAT_SUPPORT_PRODUCT}"
  	platform_version="${ROCKY_SUPPORT_PRODUCT_VERSION}"
        platform=$ID

  elif [ "$platform" = "xenserver" ]; then
    # Current XenServer 6.2 is based on CentOS 5, platform is not reset to "el" server should handle response
    platform="xenserver"
  else
    # FIXME: use "redhat"
    platform="el"
  fi

elif [ -f "/etc/system-release" ]; then
  platform=`sed 's/^\(.\+\) release.\+/\1/' /etc/system-release | tr 'A-Z' 'a-z'`
  platform_version=`sed 's/^.\+ release \([.0-9]\+\).*/\1/' /etc/system-release | tr 'A-Z' 'a-z'`
  case $platform in amazon*) # sh compat method of checking for a substring
    . /etc/os-release
    platform_version=$VERSION_ID

    case $platform_version in
      "2022"|"2023")
        platform="amazon"
      ;;
      "2")
        platform="el"
        platform_version="7"
        ;;
      *)
        platform="el"

        # VERSION_ID will match YYYY.MM for Amazon Linux AMIs
        platform_version="6"
        ;;
    esac
  esac


# Apple macOS
elif [ -f "/usr/bin/sw_vers" ]; then
  platform="mac_os_x"
  # Matching the tab-space with sed is error-prone
  platform_version=`sw_vers | awk '/^ProductVersion:/ { print $2 }' | cut -d. -f1,2`
elif [ -f "/etc/release" ]; then
  machine=`/usr/bin/uname -p`
  if grep SmartOS /etc/release >/dev/null; then
    platform="smartos"
    platform_version=`grep ^Image /etc/product | awk '{ print $3 }'`
  else
    platform="solaris2"
    platform_version=`/usr/bin/uname -r`
  fi
elif [ -f "/etc/SuSE-release" ]; then
  if grep 'Enterprise' /etc/SuSE-release >/dev/null;
  then
      platform="sles"
      platform_version=`awk '/^VERSION/ {V = $3}; /^PATCHLEVEL/ {P = $3}; END {print V "." P}' /etc/SuSE-release`
  else # opensuse 43 only. 15 ships with /etc/os-release only
      platform="opensuseleap"
      platform_version=`awk '/^VERSION =/ { print $3 }' /etc/SuSE-release`
  fi
elif [ "$os" = "FreeBSD" ]; then
  platform="freebsd"
  platform_version=`uname -r | sed 's/-.*//'`
elif [ "$os" = "AIX" ]; then
  platform="aix"
  platform_version="`uname -v`.`uname -r`"
  machine="powerpc"
elif [ -f "/etc/os-release" ]; then
  . /etc/os-release
  if [ -n "$CISCO_RELEASE_INFO" ]; then
    . "$CISCO_RELEASE_INFO"
  fi

  platform=$ID

  # VERSION_ID is always the preferred variable to use, but not
  # every distro has it so fallback to VERSION
  if [ -n "$VERSION_ID" ]; then
    platform_version=$VERSION_ID
  else
    platform_version=$VERSION
  fi
fi

if [ -z "$platform" ]; then
  echo "Unable to determine platform version!"
  report_bug
  exit 1
fi

#
# NOTE: platform mangling in the install.sh is DEPRECATED
#
# - install.sh should be true to ohai and should not remap
#   platform or platform versions.
#
# - remapping platform and mangling platform version numbers is
#   now the complete responsibility of the server-side endpoints
#

major_version=`echo "$platform_version" | cut -d. -f1`
case $platform in
  # FIXME: should remove this case statement completely
  "el")
    # FIXME:  "el" is deprecated, should use "redhat"
    platform_version=$major_version
    ;;
  "rocky")
    platform_version=$major_version
    ;;
  "debian")
    if [ "$major_version" = "5" ]; then
      # This is here for potential back-compat.
      # We do not have 5 in versions we publish for anymore but we
      # might have it for earlier versions.
      platform_version="6"
    else
      platform_version=$major_version
    fi
    ;;
  "freebsd")
    platform_version=$major_version
    ;;
  "sles")
    platform_version=$major_version
    ;;
  "opensuseleap")
    platform_version=$major_version
    ;;
esac

# normalize the architecture we detected
case $machine in
  "arm64"|"aarch64")
    machine="aarch64"
    ;;
  "x86_64"|"amd64"|"x64")
    machine="x86_64"
    ;;
  "i386"|"i86pc"|"x86"|"i686")
    machine="i386"
    ;;
  "sparc"|"sun4u"|"sun4v")
    machine="sparc"
    ;;
esac

# AlmaLinux 10 ships a separate x86-64-v2 package set for older CPUs.
# `uname -m` reports x86_64 on both variants, so key off the marker file
# that only the x86_64_v2 build of almalinux-release installs.
if [ "$machine" = "x86_64" ] && [ -f "/etc/rpm/macros.x86_64_v2" ]; then
  machine="x86_64_v2"
fi

if [ -z "$platform_version" ]; then
  echo "Unable to determine platform version!"
  report_bug
  exit 1
fi

if [ "$platform" = "solaris2" ]; then
  # hack up the path on Solaris to find wget, pkgadd
  PATH=/usr/sfw/bin:/usr/sbin:$PATH
  export PATH
fi

echo "$platform $platform_version $machine"

############
# end of platform_detection.sh
############


# All of the download utilities in this script load common proxy env vars.
# If variables are set they will override any existing env vars.
# Otherwise, default proxy env vars will be loaded by the respective
# download utility.

if [ -n "$https_proxy" ]; then
  echo "setting https_proxy: $https_proxy"
  HTTPS_PROXY=$https_proxy
  export HTTPS_PROXY
  export https_proxy
fi

if [ -n "$http_proxy" ]; then
  echo "setting http_proxy: $http_proxy"
  HTTP_PROXY=$http_proxy
  export HTTP_PROXY
  export http_proxy
fi

if [ -n "$ftp_proxy" ]; then
  echo "setting ftp_proxy: $ftp_proxy"
  FTP_PROXY=$ftp_proxy
  export FTP_PROXY
  export ftp_proxy
fi

if [ -n "$no_proxy" ]; then
  echo "setting no_proxy: $no_proxy"
  NO_PROXY=$no_proxy
  export NO_PROXY
  export no_proxy
fi


# fetch_metadata.sh
############
# This section calls omnitruck to get the information about the build to be
#   installed.
#
#  EXAMPLE
#    curl -L 'https://omnitruck.cinc.sh/install.sh' | sudo bash -s --  -P cinc -c stable
#
# Gets the download url and SHA256 checksum for the latest stable release of Cinc Workstation.
#   EXAMPLE
#     curl -L 'https://omnitruck.cinc.sh/install.sh' | sudo bash -s --  -P cinc-workstation -c stable
#
# Inputs:
# $base_api_url:
# $channel:
# $project:
# $version:
# $platform:
# $platform_version:
# $machine:
# $tmp_dir:
#
# Outputs:
# $download_url:
# $sha256:
############

if [ -z "$download_url_override" ]; then
  echo "Getting information for $project $channel $version for $platform..."

  metadata_filename="$tmp_dir/metadata.txt"

  # Set base_api_url from option if not already set via CLI parameter
  if [ -z "$base_api_url" ]; then
    base_api_url="https://omnitruck.cinc.sh"
  fi


  if [ -z "$base_api_url" ]; then
    base_api_url="https://omnitruck.cinc.sh"
  fi

  metadata_url="$base_api_url/$channel/$project/metadata?v=$version&p=$platform&pv=$platform_version&m=$machine"

  do_download "$metadata_url" "$metadata_filename"

  cat "$metadata_filename"

  echo ""

  # Parse text response from omnitruck
  if grep '^url' "$metadata_filename" > /dev/null && grep '^sha256' "$metadata_filename" > /dev/null; then
    echo "downloaded metadata file looks valid..."
    download_url=`awk '$1 == "url" { print $2 }' "$metadata_filename"`
    sha256=`awk '$1 == "sha256" { print $2 }' "$metadata_filename"`
    if [ -z "$version" ]; then
      version=`awk '$1 == "version" { print $2 }' "$metadata_filename"`
    fi
  else
    echo "downloaded metadata file is corrupted or an uncaught error was encountered in downloading the file..."
    # this generally means one of the download methods downloaded a 404 or something like that and then reported a successful exit code,
    # and this should be fixed in the function that was doing the download.
    report_bug
    exit 1
  fi
else
  download_url=$download_url_override
  # Set sha256 to empty string if checksum not set
  sha256=${checksum=""}
fi

############
# end of fetch_metadata.sh
############


# fetch_package.sh
############
# This section fetches a package from the CINC mirror at ghcr.io first and
# falls back to the upstream $download_url when the mirror cannot serve it.
#
# Inputs:
# $download_url: Upstream URL from metadata, used as the fallback.
# $sha256: SHA256 from metadata, used to address the GHCR blob.
# $tmp_dir:
# Optional Inputs:
# $cmdline_filename: Name of the package downloaded on local disk.
# $cmdline_dl_dir: Name of the directory downloaded package will be saved to on local disk.
#
# Outputs:
# $download_filename: Name of the downloaded file on local disk.
# $filetype: Type of the file downloaded.
############

# Determine filetype from the original download URL in metadata.
if [ -n "$download_url_override" ]; then
  filetype_source="$download_url_override"
else
  filetype_source="$download_url"
fi

case "$filetype_source" in
  *.deb) filetype="deb" ;;
  *.rpm) filetype="rpm" ;;
  *.dmg) filetype="dmg" ;;
  *.pkg) filetype="pkg" ;;
  *)
    # Fallback to platform-based detection
    case "$platform" in
      "ubuntu"|"debian") filetype="deb" ;;
      "el"|"centos"|"rhel"|"fedora"|"rocky"|"amazon") filetype="rpm" ;;
      "mac_os_x") filetype="dmg" ;;
      *) filetype="deb" ;;
    esac
    ;;
esac

# GHCR blobs carry no filename or extension, so synthesize the local name.
if [ "$filetype" = "dmg" ]; then
  filename="${project}-${version}-1.${machine}.${filetype}"
else
  if [ "$filetype" = "deb" ]; then
    # Map normalized machine arch to Debian package arch naming
    deb_arch="$machine"
    case "$machine" in
      aarch64) deb_arch="arm64" ;;
      x86_64)  deb_arch="amd64" ;;
    esac
    # Fallback synthesized filename (will be overwritten if we can adopt upstream name)
    filename="${project}_${version}_${platform}_${platform_version}_${deb_arch}.${filetype}"
    # If upstream metadata (packages.cinc.sh) provides an original filename (includes revision like -1), adopt it
    original_filename=`basename "$download_url"`
    case "$original_filename" in
      ${project}_*_${deb_arch}.deb)
        filename="$original_filename"
        ;;
    esac
  else
    filename="${project}_${version}_${platform}_${platform_version}_${machine}.${filetype}"
  fi
fi

# use either $tmp_dir, the provided directory (-d) or the provided filename (-f)
if [ -n "$cmdline_filename" ]; then
  download_filename="$cmdline_filename"
elif [ -n "$cmdline_dl_dir" ]; then
  download_filename="$cmdline_dl_dir/$filename"
else
  download_filename="$tmp_dir/$filename"
fi

# ensure the parent directory where we download the installer always exists
download_dir=`dirname "$download_filename"`
(umask 077 && mkdir -p "$download_dir") || exit 1

# Fetch one blob from ghcr.io by SHA256. Returns non-zero when the mirror
# cannot serve it, so the caller can fall back to the upstream URL.
do_ghcr_blob_download() {
  ghcr_sha256="$1"
  ghcr_output_file="$2"
  ghcr_project="$3"
  ghcr_registry="ghcr.io"
  ghcr_repo_path="rmoriz/cinc-mirror/${ghcr_project}"
  ghcr_blob_url="https://${ghcr_registry}/v2/${ghcr_repo_path}/blobs/sha256:${ghcr_sha256}"

  # The mirror path needs curl for the token request and authenticated blob.
  exists curl || return 1

  echo "Fetching ${ghcr_registry}/${ghcr_repo_path}@sha256:${ghcr_sha256}"
  echo "Downloading to $ghcr_output_file..."

  ghcr_token=""
  ghcr_auth_url="https://${ghcr_registry}/token?service=${ghcr_registry}&scope=repository:${ghcr_repo_path}:pull"
  ghcr_token_response=`curl -fsS "$ghcr_auth_url" 2>/dev/null || true`
  if [ -n "$ghcr_token_response" ]; then
    ghcr_token=`printf '%s' "$ghcr_token_response" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'`
  fi

  if [ -n "$ghcr_token" ]; then
    curl -fsSL --retry 3 -H "Authorization: Bearer ${ghcr_token}" -o "$ghcr_output_file" "$ghcr_blob_url"
  else
    curl -fsSL --retry 3 -o "$ghcr_output_file" "$ghcr_blob_url"
  fi
}

# check if we have that file locally available and if so verify the checksum
cached_file_available="false"
verify_checksum="true"

if [ -f "$download_filename" ]; then
  echo "$download_filename exists"
  if [ -z "$sha256" ]; then
    echo "Checksum not specified, ignoring existing file"
    cached_file_available="false"
    verify_checksum="false"
  elif do_checksum "$download_filename" "$sha256"; then
    echo "Checksum match, using existing file"
    cached_file_available="true"
    verify_checksum="false"
  else
    echo "Checksum mismatch, ignoring existing file"
    cached_file_available="false"
    verify_checksum="true"
  fi
fi

if [ "$cached_file_available" != "true" ]; then
  if [ -n "$download_url_override" ]; then
    # Use traditional download method for URL override
    do_download "$download_url_override" "$download_filename"
  else
    # Prefer the CINC mirror; fall back to upstream when it cannot serve us.
    if do_ghcr_blob_download "$sha256" "$download_filename" "$project"; then
      echo "Downloaded from the CINC mirror."
    else
      echo "CINC mirror download failed; falling back to $download_url"
      rm -f "$download_filename"
      do_download "$download_url" "$download_filename"
    fi

    # For DMG files, the blob contains the actual DMG data
    # but we need to ensure it has the right extension for the installer
    if [ "$filetype" = "dmg" ] && [ "${download_filename##*.}" != "dmg" ]; then
      # Rename the file to have .dmg extension
      dmg_filename="${download_filename%.*}.dmg"
      mv "$download_filename" "$dmg_filename"
      download_filename="$dmg_filename"
    fi
  fi
fi

if [ "$verify_checksum" = "true" ]; then
  if [ -z "$sha256" ]; then
    echo "Skipping checksum verification - no checksum provided"
  else
    do_checksum "$download_filename" "$sha256" || checksum_mismatch
  fi
fi

############
# end of fetch_package.sh
############


# install_package.sh
############
# Installs a package and removed the temp directory.
#
# Inputs:
# $download_filename: Name of the file to be installed.
# $filetype: Type of the file to be installed.
# $version: The version requested. Used only for warning user if not set.
############

if [ -z "$version" ] && [ "$CI" != "true" ]; then
  echo
  echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
  echo
  echo "You are installing a package without a version pin.  If you are installing"
  echo "on production servers via an automated process this is DANGEROUS and you will"
  echo "be upgraded without warning on new releases, even to new major releases."
  echo "Letting the version float is only appropriate in test, development or"
  echo "CI/CD environments."
  echo
  echo "WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
  echo
fi

install_file $filetype "$download_filename"

if [ -n "$tmp_dir" ]; then
  rm -r "$tmp_dir"
fi

############
# end of install_package.sh
############
