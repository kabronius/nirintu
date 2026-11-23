/* Nirintu installation slideshow: what the installed system offers. Italian or English by locale. */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    readonly property bool it: Qt.locale().name.substring(0, 2) === "it"
    readonly property color bg: "#11112d"
    readonly property color title: "#fff59b"
    readonly property color body: "#e6e6f8"
    readonly property color accent: "#a9aefe"

    function t(itText, enText) { return it ? itText : enText; }

    // Slides cover only 90% x 70% of the presentation: the rest would show the view's white clear colour.
    Rectangle {
        anchors.fill: parent
        color: presentation.bg
        z: -1
    }

    Timer {
        interval: 9000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Component {
        id: page
        Rectangle {
            property string heading
            property string bodyText
            property string keys
            color: presentation.bg
            anchors.fill: parent
            Column {
                anchors.centerIn: parent
                width: parent.width * 0.78
                spacing: 18
                Image {
                    source: "logo.png"
                    width: 96; height: 96
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: heading
                    color: presentation.title
                    font.pixelSize: 28; font.bold: true
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Text {
                    text: bodyText
                    color: presentation.body
                    font.pixelSize: 16
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }
                Text {
                    text: keys
                    visible: keys !== ""
                    color: presentation.accent
                    font.pixelSize: 15; font.family: "monospace"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Slide {
        Loader { anchors.fill: parent; sourceComponent: page
            onLoaded: { item.heading = presentation.t("Benvenuto in Nirintu", "Welcome to Nirintu");
                        item.bodyText = presentation.t("Ubuntu 24.04 LTS senza snap, con il compositor niri e la shell Noctalia. L'installazione richiede qualche minuto.",
                                                   "Ubuntu 24.04 LTS without snap, with the niri compositor and the Noctalia shell. Installation takes a few minutes.");
                        item.keys = ""; } } }

    Slide {
        Loader { anchors.fill: parent; sourceComponent: page
            onLoaded: { item.heading = presentation.t("Finestre in colonne", "Windows in columns");
                        item.bodyText = presentation.t("niri dispone le finestre in colonne su una striscia che scorre in orizzontale: una nuova finestra non ridimensiona le altre.",
                                                   "niri lays windows out in columns on a strip that scrolls horizontally: a new window never resizes the others.");
                        item.keys = "Super+T " + presentation.t("terminale", "terminal") + "   Super+←/→ " + presentation.t("colonne", "columns") + "   Super+O " + presentation.t("panoramica", "overview"); } } }

    Slide {
        Loader { anchors.fill: parent; sourceComponent: page
            onLoaded: { item.heading = "Noctalia";
                        item.bodyText = presentation.t("Barra, avvio delle applicazioni, notifiche, blocco schermo e impostazioni in un'unica shell. I colori seguono lo sfondo.",
                                                   "Bar, launcher, notifications, lock screen and settings in a single shell. Colours follow the wallpaper.");
                        item.keys = "Super+D " + presentation.t("applicazioni", "launcher") + "   Super+Alt+L " + presentation.t("blocca", "lock") + "   Super+Shift+/ " + presentation.t("scorciatoie", "shortcuts"); } } }

    Slide {
        Loader { anchors.fill: parent; sourceComponent: page
            onLoaded: { item.heading = presentation.t("Applicazioni", "Applications");
                        item.bodyText = presentation.t("Pacchetti .deb dall'archivio Ubuntu, Firefox dal repository di Mozilla e le applicazioni di Flathub tramite Flatpak. snapd non viene mai installato.",
                                                   "Ubuntu .deb packages, Firefox from Mozilla's repository and Flathub applications through Flatpak. snapd is never installed.");
                        item.keys = "flatpak install flathub <app>"; } } }

    Slide {
        Loader { anchors.fill: parent; sourceComponent: page
            onLoaded: { item.heading = presentation.t("Avvio", "Boot");
                        item.bodyText = presentation.t("Il tema di GRUB è scelto in base al produttore del computer e gli altri sistemi installati compaiono nel menu di avvio.",
                                                   "The GRUB theme is chosen from the computer's vendor and other installed systems appear in the boot menu.");
                        item.keys = "nirintu-grub-theme list"; } } }

    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() { }
}
