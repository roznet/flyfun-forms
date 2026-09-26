package aero.flyfun.forms.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldDefaults
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.PaneScaffoldDirective
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldDestinationItem
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.material3.adaptive.layout.calculateThreePaneScaffoldValue
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * The window's pane layout: one pane on a phone, list and detail side by side
 * once there is room (a tablet, an unfolded foldable, a phone in landscape on
 * some sizes).
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun paneDirective(): PaneScaffoldDirective = calculatePaneScaffoldDirective(currentWindowAdaptiveInfo())

/** Whether list and detail show together. */
@Composable
fun isTwoPane(): Boolean = paneDirective().maxHorizontalPartitions > 1

/**
 * A list and the item open from it, laid out by [ListDetailPaneScaffold].
 *
 * The navigation back stack is the navigator: a tab's list route shows the list
 * (and [placeholder] beside it when there is room), an item's route shows the
 * item (and the list beside it). On a phone that is exactly one screen per
 * route, as before; on a tablet the list stays put while items change. Keeping
 * the back stack in charge leaves every screen's ViewModel scoped to its route,
 * and Back, the unsaved-changes prompt and the pickers work as on a phone.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun ListDetail(
    showingDetail: Boolean,
    list: @Composable () -> Unit,
    detail: @Composable () -> Unit,
) {
    val directive = paneDirective()
    val value = calculateThreePaneScaffoldValue(
        maxHorizontalPartitions = directive.maxHorizontalPartitions,
        adaptStrategies = ListDetailPaneScaffoldDefaults.adaptStrategies(),
        currentDestination = ThreePaneScaffoldDestinationItem(
            if (showingDetail) ListDetailPaneScaffoldRole.Detail else ListDetailPaneScaffoldRole.List,
        ),
    )
    ListDetailPaneScaffold(
        directive = directive,
        value = value,
        listPane = { AnimatedPane { list() } },
        detailPane = { AnimatedPane { detail() } },
    )
}

/** The detail pane before anything is picked from the list. */
@Composable
fun NothingSelected(text: String) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxSize().padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
