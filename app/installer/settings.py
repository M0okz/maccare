from pathlib import Path

app = Path(defines['app']).resolve()
assets = Path(defines['assets']).resolve()
format = 'UDZO'
filesystem = 'HFS+'
files = [str(app)]
symlinks = {'Applications': '/Applications'}
background = str(assets / 'background.tiff')
icon = str(assets / 'MacCare.icns')
# Masquer l'extension via SetFile ajouterait FinderInfo au paquet après signature.
# Le bundle reste inchangé et conserve son nom MacCare.app.
hide_extensions = []
# Réserve 70 points pour les barres Finder que les préférences utilisateur peuvent imposer.
window_rect = ((160, 160), (680, 530))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
icon_size = 112
text_size = 14
label_pos = 'bottom'
icon_locations = {'MacCare.app': (190, 235), 'Applications': (490, 235)}
