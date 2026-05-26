/*
    Window Filter — configuration page.
    SPDX-License-Identifier: MIT
*/

import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.13

import org.kde.plasma.plasmoid 2.0
import org.kde.kirigami 2.20 as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    // cfg_<key> properties are auto-synced with Plasmoid.configuration.<key>.
    property string cfg_sortMode: Plasmoid.configuration.sortMode
    property alias cfg_keepOpenOnActivate: keepOpenCheck.checked
    property alias cfg_showActivityColumn: activityColumnCheck.checked

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.ComboBox {
            id: sortCombo
            Kirigami.FormData.label: i18n("Default order:")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "alpha",    text: i18n("Alphabetical") },
                { value: "lru",      text: i18n("Most recently used") },
                { value: "activity", text: i18n("By activity") }
            ]
            currentIndex: {
                for (let i = 0; i < model.length; i++)
                    if (model[i].value === cfg_sortMode)
                        return i;
                return 0;
            }
            onActivated: cfg_sortMode = model[currentIndex].value
        }

        QQC2.CheckBox {
            id: activityColumnCheck
            Kirigami.FormData.label: i18n("Window list:")
            text: i18n("Show the Activity of each window")
        }

        QQC2.CheckBox {
            id: keepOpenCheck
            text: i18n("Keep the list open after focusing a window")
        }
    }
}
