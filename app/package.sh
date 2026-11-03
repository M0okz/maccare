#!/usr/bin/env bash
# Assemble build/MacCare.app depuis le binaire SwiftPM, puis le signe.
#
# Une signature propre est indispensable : macOS lie les autorisations (Accès complet au disque,
# Automatisation) à l'identité de signature de l'app. Avec la signature ad hoc du linker, le paquet
# est invalide et macOS recrée l'autorisation en « Refusé » à chaque lancement.
#
# Identité : variable MACCARE_SIGN_IDENTITY (empreinte ou nom), sinon la première identité
# « Apple Development » valide du trousseau. Elle reste identique d'un build à l'autre, donc
# l'autorisation survit aux recompilations. Pour distribuer, utilisez une identité
# « Developer ID Application » (et notarisez).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

bin="app/.build/release/MacCare"
helper_bin="app/.build/release/MacCareHelper"
if [ ! -x "$bin" ] || [ ! -x "$helper_bin" ]; then
    echo "Binaire introuvable : lancez d'abord app/build.sh" >&2
    exit 1
fi

# Un chemin explicite permet de préparer le DMG sans remplacer le paquet actuellement ouvert.
app="$(python3 - "$repo_root" "${1:-build/MacCare.app}" <<'PYCODE'
from pathlib import Path
import sys
root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
if not output.is_relative_to(root / "build") or output.name != "MacCare.app":
    raise SystemExit("Le paquet doit être un MacCare.app placé sous build/.")
print(output)
PYCODE
)"
assets="$repo_root/build/installer-assets"
mkdir -p "$assets"
swift app/installer/render-assets.swift "$assets"
iconutil -c icns "$assets/MacCare.iconset" -o "$assets/MacCare.icns"
rm -rf "$assets/MacCare.iconset"
echo "==> Assemblage de $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/LaunchDaemons"
cp "$bin" "$app/Contents/MacOS/MacCare"
cp app/Info.plist "$app/Contents/Info.plist"
python3 app/release/configure_bundle.py "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$assets/MacCare.icns" "$app/Contents/Resources/MacCare.icns"
# Assistant privilégié (nettoyage système) : l'exécutable vit dans le paquet et le plist launchd
# est enregistré par SMAppService.daemon (voir docs/architecture.md). Il disparaît avec l'app.
cp "$helper_bin" "$app/Contents/MacOS/MacCareHelper"
cp app/Helper/org.maccare.helper.plist "$app/Contents/Library/LaunchDaemons/org.maccare.helper.plist"
# Règles de nettoyage au format ouvert : lues par l'app au démarrage (voir CleaningCategory.swift).
cp -R core/rules "$app/Contents/Resources/rules"

# SwiftPM lie le framework, mais l’assemblage manuel doit l’embarquer et préserver ses liens.
sparkle="app/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$sparkle" ]; then
    echo "Framework Sparkle absent : lancez app/build.sh." >&2
    exit 1
fi
mkdir -p "$app/Contents/Frameworks"
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
cp app/.build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE"

identity="${MACCARE_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning \
        | grep "Apple Development" | grep -v REVOKED | head -1 | awk '{print $2}' || true)"
fi

# L'assistant et les outils Sparkle sont signés de l’intérieur vers l’extérieur.
# La distribution active le runtime durci et conserve explicitement l’Automatisation.
sign_options=(--force)
app_options=(--identifier org.maccare.app)
if [ "${MACCARE_DISTRIBUTION:-0}" = "1" ]; then
    if [ -z "$identity" ] || ! security find-identity -v -p codesigning | grep -F "$identity" | grep -q 'Developer ID Application'; then
        echo "La distribution exige une identité Developer ID Application valide." >&2
        exit 1
    fi
    sign_options+=(--timestamp)
    app_options+=(--options runtime --entitlements app/Release.entitlements)
fi
if [ -n "$identity" ]; then
    echo "==> Signature avec l'identité $identity"
    framework="$app/Contents/Frameworks/Sparkle.framework"
    for nested in "$framework/Versions/B/XPCServices/Downloader.xpc" \
                  "$framework/Versions/B/XPCServices/Installer.xpc" \
                  "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" "$framework"; do
        codesign "${sign_options[@]}" --sign "$identity" --options runtime \
            --preserve-metadata=entitlements "$nested"
    done
    codesign "${sign_options[@]}" --sign "$identity" --identifier org.maccare.helper --options runtime \
        "$app/Contents/MacOS/MacCareHelper"
    codesign "${sign_options[@]}" --sign "$identity" "${app_options[@]}" "$app"
else
    echo "==> Aucune identité de signature trouvée : signature ad hoc."
    echo "    Les autorisations macOS ne tiendront pas d'un build à l'autre ;"
    echo "    l'assistant de nettoyage système ne pourra pas être activé (exigence de signature)."
    codesign --force --sign - --identifier org.maccare.helper "$app/Contents/MacOS/MacCareHelper"
    codesign --force --sign - --identifier org.maccare.app "$app"
fi

codesign --verify --deep --strict "$app"
echo "==> Signature valide"
codesign -dr - "$app" 2>&1 | sed -n 's/^designated => /    Exigence : /p'
echo "==> Assistant : $(codesign -dv "$app/Contents/MacOS/MacCareHelper" 2>&1 | grep -E 'Identifier=|flags=' | tr '\n' ' ')"
echo "==> OK : $app"
