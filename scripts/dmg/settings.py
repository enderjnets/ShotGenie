# Ajustes de dmgbuild para el DMG de ShotGenie: una ventana blanca de 560×360 con el texto en el
# fondo y un único icono, «Install ShotGenie», centrado debajo (misma disposición que el
# instalador de ChatGPT). Lo usa scripts/make-dmg.sh, que pasa las rutas con -D.
import os.path

app = defines["app"]
files = [app]
icon = defines["icon"]
background = defines["background"]
format = "UDZO"

window_rect = ((100, 100), (560, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 128
text_size = 12
label_pos = "bottom"
icon_locations = {os.path.basename(app): (280, 230)}
