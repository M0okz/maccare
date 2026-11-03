"""Contrôle le contrat Finder dans l'image montée, pas seulement le script de réglages."""
from pathlib import Path
import sys
from ds_store import DSStore

volume = Path(sys.argv[1])
with DSStore.open(str(volume / '.DS_Store'), 'r') as store:
    assert store['MacCare.app']['Iloc'] == (190, 235), 'Position de MacCare inattendue'
    assert store['Applications']['Iloc'] == (490, 235), 'Position d’Applications inattendue'
    view = store['.']['icvp']
    assert view['backgroundType'] == 2, 'Fond illustré absent'
    assert view['iconSize'] == 112, 'Taille des icônes incorrecte'
print('Disposition Finder vérifiée : fond, taille et positions des deux icônes.')
