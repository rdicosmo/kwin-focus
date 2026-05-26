/*
    Window Filter — a Plasma 6 applet that lists every open window across all
    virtual desktops and Activities, filterable by title/application, and
    fully keyboard-navigable. Clicking or Enter focuses the window (KWin
    switches desktop AND Activity automatically via requestActivate()).

    (C) Roberto Di Cosmo 2026 -  SPDX-License-Identifier: MIT

    NB: unlike the cli/kwin-focus tool, an applet runs *inside* plasmashell,
    so it uses TaskManager.TasksModel directly — none of the KWin-scripting /
    journal exfiltration dance is needed here.
*/

import QtQml 2.15
import QtQuick 2.15
import QtQuick.Layouts 1.10
import QtQuick.Controls 2.15 as QQC2

import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami 2.20 as Kirigami
import org.kde.taskmanager 0.1 as TaskManager
import org.kde.kitemmodels as KItemModels
import org.kde.activities 0.1 as Activities

PlasmoidItem {
    id: root

    Plasmoid.icon: "preferences-system-windows"
    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 12

    // Pin: keep the popup open across focus changes so you can keep navigating.
    // hideOnWindowDeactivate is a PlasmoidItem property (not on the attached Plasmoid).
    hideOnWindowDeactivate: !Plasmoid.configuration.keepOpenOnActivate

    // The text typed in the search field; drives the proxy filter.
    property string filterText: ""

    // Map the persisted sort-mode string to the TasksModel enum.
    function tmSortMode(s) {
        if (s === "lru")      return TaskManager.TasksModel.SortLastActivated;
        if (s === "activity") return TaskManager.TasksModel.SortActivity;
        return TaskManager.TasksModel.SortAlpha;
    }
    // Cycle the persisted sort mode (alpha -> lru -> activity -> alpha).
    function cycleSort() {
        const order = ["alpha", "lru", "activity"];
        const i = order.indexOf(Plasmoid.configuration.sortMode);
        Plasmoid.configuration.sortMode = order[(i + 1) % order.length];
    }
    function sortLabel(s) {
        if (s === "lru")      return i18n("Recent");
        if (s === "activity") return i18n("Activity");
        return i18n("A–Z");
    }

    // ---- Activity id -> name resolution (for the activity column + filtering) ----
    property var activityNames: ({})

    Activities.ActivityModel { id: activityModel }

    // Each activity row exposes id/name (confirmed role names: model.id/model.name).
    Instantiator {
        model: activityModel
        delegate: QtObject {
            readonly property string aid: model.id
            readonly property string aname: model.name
            function sync() {
                const m = Object.assign({}, root.activityNames);
                m[aid] = aname;
                root.activityNames = m;   // new reference so bindings re-evaluate
            }
            onAnameChanged: sync()
            Component.onCompleted: sync()
        }
    }

    // Column text: "All" when the window is on every activity.
    function activityDisplay(acts) {
        if (!acts || acts.length === 0)
            return i18n("All");
        let names = [];
        for (let i = 0; i < acts.length; i++)
            names.push(root.activityNames[acts[i]] || acts[i]);
        return names.join(", ");
    }
    // Activity names joined for matching in the text filter ("" when on all).
    function activityFilterText(acts) {
        if (!acts || acts.length === 0)
            return "";
        let names = [];
        for (let i = 0; i < acts.length; i++)
            names.push(root.activityNames[acts[i]] || "");
        return names.join(" ");
    }

    // All windows everywhere, ungrouped (defaults: no desktop/activity filtering).
    TaskManager.TasksModel {
        id: tasksModel
        sortMode: root.tmSortMode(Plasmoid.configuration.sortMode)
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
            const acts = root.activityFilterText(tasksModel.data(idx, TaskManager.AbstractTasksModel.Activities));
            const needle = root.filterText.toLowerCase();
            return title.toLowerCase().indexOf(needle) !== -1
                || app.toLowerCase().indexOf(needle) !== -1
                || acts.toLowerCase().indexOf(needle) !== -1;
        }
    }

    // Focus the window at the given *proxy* row, then close the popup (unless pinned).
    function activateRow(proxyRow) {
        if (proxyRow < 0 || proxyRow >= filterModel.count)
            return;
        const sourceRow = filterModel.mapToSource(filterModel.index(proxyRow, 0)).row;
        tasksModel.requestActivate(tasksModel.makeModelIndex(sourceRow));
        if (!Plasmoid.configuration.keepOpenOnActivate)
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

            // ---- header: search + sort cycle + pin ----
            RowLayout {
                Layout.fillWidth: true
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
                    Keys.onDownPressed: {
                        if (listView.count > 0) {
                            listView.currentIndex = 0;
                            listView.forceActiveFocus();
                        }
                    }
                    Keys.onReturnPressed: root.activateRow(listView.currentIndex >= 0 ? listView.currentIndex : 0)
                    Keys.onEnterPressed:  root.activateRow(listView.currentIndex >= 0 ? listView.currentIndex : 0)
                    Keys.onEscapePressed: {
                        if (text.length > 0)
                            text = "";
                        else
                            root.expanded = false;
                    }
                }

                QQC2.ToolButton {
                    id: sortButton
                    text: root.sortLabel(Plasmoid.configuration.sortMode)
                    icon.name: "view-sort"
                    onClicked: root.cycleSort()
                    QQC2.ToolTip.text: i18n("Sort order — click to cycle (Alphabetical / Recent / Activity)")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                QQC2.ToolButton {
                    id: pinButton
                    checkable: true
                    checked: Plasmoid.configuration.keepOpenOnActivate
                    icon.name: "window-pin"
                    text: i18n("Pin")
                    onToggled: Plasmoid.configuration.keepOpenOnActivate = checked
                    QQC2.ToolTip.text: i18n("Keep the list open after focusing a window")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // ---- the window list ----
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
                            // Activity column (right-aligned, dim) — optional.
                            PlasmaComponents.Label {
                                visible: Plasmoid.configuration.showActivityColumn
                                Layout.alignment: Qt.AlignVCenter
                                Layout.maximumWidth: Kirigami.Units.gridUnit * 8
                                horizontalAlignment: Text.AlignRight
                                text: root.activityDisplay(model.Activities)
                                opacity: 0.6
                                font: Kirigami.Theme.smallFont
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }
                        }
                        onClicked: root.activateRow(index)
                    }

                    Keys.onReturnPressed: root.activateRow(currentIndex)
                    Keys.onEnterPressed:  root.activateRow(currentIndex)
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
