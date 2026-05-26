/*
    Window Filter — a Plasma 6 applet that lists every open window across all
    virtual desktops and Activities, filterable by title/application, and
    fully keyboard-navigable. Clicking or Enter focuses the window (KWin
    switches desktop AND Activity automatically via requestActivate()).

    (C) Roberto Di Cosmo 2026 -  SPDX-License-Identifier: MIT

    NB: unlike the ~/bin/kwin-focus CLI, an applet runs *inside* plasmashell,
    so it uses TaskManager.TasksModel directly — none of the KWin-scripting /
    journal exfiltration dance is needed here.
*/

import QtQuick 2.15
import QtQuick.Layouts 1.10

import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami 2.20 as Kirigami
import org.kde.taskmanager 0.1 as TaskManager
import org.kde.kitemmodels as KItemModels

PlasmoidItem {
    id: root

    Plasmoid.icon: "preferences-system-windows"
    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 12

    // The text typed in the search field; drives the proxy filter.
    property string filterText: ""

    // All windows everywhere, ungrouped (defaults: no desktop/activity filtering).
    TaskManager.TasksModel {
        id: tasksModel
        sortMode: TaskManager.TasksModel.SortAlpha
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    // Substring match on BOTH window title and application name (case-insensitive).
    KItemModels.KSortFilterProxyModel {
        id: filterModel
        sourceModel: tasksModel
        filterRowCallback: function (sourceRow, sourceParent) {
            if (root.filterText.length === 0)
                return true;
            const idx = tasksModel.index(sourceRow, 0, sourceParent);
            const title = String(tasksModel.data(idx, Qt.DisplayRole) || "");
            const app = String(tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || "");
            const needle = root.filterText.toLowerCase();
            return title.toLowerCase().indexOf(needle) !== -1
                || app.toLowerCase().indexOf(needle) !== -1;
        }
    }

    // Focus the window at the given *proxy* row, then close the popup.
    function activateRow(proxyRow) {
        if (proxyRow < 0 || proxyRow >= filterModel.count)
            return;
        const sourceRow = filterModel.mapToSource(filterModel.index(proxyRow, 0)).row;
        tasksModel.requestActivate(tasksModel.makeModelIndex(sourceRow));
        root.expanded = false;
    }

    fullRepresentation: FocusScope {
        id: dialog
        focus: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24

        // Reset and focus the search field each time the popup opens.
        Connections {
            target: root
            function onExpandedChanged() {
                if (root.expanded) {
                    searchField.text = "";
                    listView.currentIndex = 0;
                    searchField.forceActiveFocus();
                }
            }
        }
        Component.onCompleted: if (root.expanded) searchField.forceActiveFocus()

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.SearchField {
                id: searchField
                Layout.fillWidth: true
                focus: true
                placeholderText: i18n("Filter by title or application…")

                onTextChanged: {
                    root.filterText = text;
                    filterModel.invalidateFilter();
                    listView.currentIndex = filterModel.count > 0 ? 0 : -1;
                }
                // Down arrow dives into the result list.
                Keys.onDownPressed: {
                    if (listView.count > 0) {
                        listView.currentIndex = 0;
                        listView.forceActiveFocus();
                    }
                }
                // Enter activates the highlighted row (first one by default).
                Keys.onReturnPressed: root.activateRow(listView.currentIndex >= 0 ? listView.currentIndex : 0)
                Keys.onEnterPressed:  root.activateRow(listView.currentIndex >= 0 ? listView.currentIndex : 0)
                Keys.onEscapePressed: {
                    if (text.length > 0)
                        text = "";
                    else
                        root.expanded = false;
                }
            }

            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: listView
                    clip: true
                    model: filterModel
                    currentIndex: 0
                    keyNavigationEnabled: true
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: PlasmaComponents.ItemDelegate {
                        width: ListView.view.width
                        highlighted: ListView.isCurrentItem

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                id: icon
                                source: model.decoration
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                visible: valid
                            }
                            Kirigami.Icon {
                                source: "preferences-system-windows"
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                visible: !icon.valid
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: model.display
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    opacity: model.IsMinimized ? 0.6 : 1.0
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: (model.AppName !== undefined ? model.AppName : "")
                                    visible: text.length > 0 && text !== model.display
                                    opacity: 0.6
                                    font: Kirigami.Theme.smallFont
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        onClicked: root.activateRow(index)
                    }

                    Keys.onReturnPressed: root.activateRow(currentIndex)
                    Keys.onEnterPressed:  root.activateRow(currentIndex)
                    // Up at the top hands focus back to the search field.
                    Keys.onUpPressed: {
                        if (currentIndex <= 0) {
                            currentIndex = 0;
                            searchField.forceActiveFocus();
                        } else {
                            currentIndex = currentIndex - 1;
                        }
                    }
                    Keys.onEscapePressed: {
                        searchField.text = "";
                        searchField.forceActiveFocus();
                    }

                    PlasmaComponents.Label {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 2
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        opacity: 0.6
                        visible: listView.count === 0
                        text: root.filterText.length > 0
                              ? i18n("No windows match “%1”.", root.filterText)
                              : i18n("No open windows.")
                    }
                }
            }
        }
    }
}
