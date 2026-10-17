#!/usr/bin/env bash
# Builds Glyph the way F-Droid's fdroiddata CI does, inside its buildserver
# image (registry.gitlab.com/fdroid/fdroidserver:buildserver-trixie).
# Usage (in that container): tool/fdroid_check.sh <glyph checkout> <commit sha>
# The recipe in docs/launch/fdroid/ is pointed at <commit sha> and the version
# in that commit's pubspec.yaml, so any commit can be checked before a tag.
set -euxo pipefail

glyph=$1
commit=$2
appid=dev.spandankumar.glyph

line=$(grep -E '^version:' "$glyph/pubspec.yaml")
name=$(sed -E 's/^version:[[:space:]]*([^+]+)\+.*/\1/' <<<"$line")
code=$(( $(sed -E 's/.*\+([0-9]+).*/\1/' <<<"$line") + 2000 ))

apt-get update
apt-get install -y sudo openjdk-21-jdk-headless
update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java
source /etc/profile.d/bsenv.sh

data=/builds/fdroiddata
git clone --depth 1 https://gitlab.com/fdroid/fdroiddata.git "$data"
cd "$data"
sed -E -e "s/^( +versionName:).*/\1 $name/" \
  -e "s/^( +versionCode:).*/\1 $code/" \
  -e "s/^( +commit:).*/\1 $commit/" \
  -e "s/^(CurrentVersion:).*/\1 $name/" \
  -e "s/^(CurrentVersionCode:).*/\1 $code/" \
  "$glyph/docs/launch/fdroid/$appid.yml" > "metadata/$appid.yml"
cat "metadata/$appid.yml"

# fdroidserver at the commit fdroiddata's CI pins, then latest master.
rm -rf "$fdroidserver"
git clone --shallow-since=2026-07-13 https://gitlab.com/fdroid/fdroidserver.git "$fdroidserver"
git -C "$fdroidserver" checkout -B master a35fdfddd9c66823987a410566a6101186e39c84
git -C "$fdroidserver" pull origin master --ff-only
export PATH="$fdroidserver:$PATH" PYTHONPATH="$fdroidserver:$fdroidserver/examples"
export PYTHONUNBUFFERED=true serverwebroot=/tmp
sdkmanager "platform-tools" "build-tools;31.0.0"
git -C "$home_vagrant/gradlew-fdroid" pull || true

# The same checks fdroiddata runs on a merge request.
fdroid lint "$appid"
fdroid rewritemeta "$appid"
git diff --exit-code "metadata/$appid.yml" || { echo "rewritemeta wants the formatting above"; exit 1; }

for d in logs tmp unsigned "$home_vagrant/.android" "$home_vagrant/.gradle" "$home_vagrant/metadata"; do
  mkdir -p "$d"; chown -R vagrant "$d"
done
ln -s "$data/tmp" "$home_vagrant/tmp"
ln -s "$data/srclibs" "$home_vagrant/srclibs"
mkdir -p build "$data/srclibs"
cp -R build "$home_vagrant/build"
cp "metadata/$appid.yml" "$home_vagrant/metadata/"
chown -R vagrant "$home_vagrant" "$data"
sysctl fs.inotify.max_user_watches=524288 || true
export GRADLE_USER_HOME=$home_vagrant/.gradle
fdroid="sudo --preserve-env --user vagrant env PATH=$fdroidserver:$PATH
  env PYTHONPATH=$fdroidserver:$fdroidserver/examples env PYTHONUNBUFFERED=true
  env HOME=$home_vagrant fdroid"

cd "$home_vagrant"
ln -s "$data" "$home_vagrant/fdroiddata"
$fdroid fetchsrclibs "$appid:$code" --verbose
rm "$home_vagrant/fdroiddata"
trap 'cp -R "$data/tmp/." /out/ 2>/dev/null || true; cp -R "$data/logs" /out/ 2>/dev/null || true' EXIT
(unset CI; $fdroid build --verbose --test --refresh-scanner --on-server --no-tarball "$appid:$code")
ls -la "$data/tmp"
