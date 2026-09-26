package aero.flyfun.forms.ui.common

import aero.flyfun.forms.R
import aero.flyfun.forms.auth.SignInProvider
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

/**
 * Google, then Apple: the same account either way the pilot signed in on iOS
 * or the web, so an Apple-only account can use the Android app too.
 */
@Composable
fun SignInButtons(onSignIn: (SignInProvider) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Button(onClick = { onSignIn(SignInProvider.GOOGLE) }) { Text(stringResource(R.string.common_sign_in_with_google)) }
        OutlinedButton(onClick = { onSignIn(SignInProvider.APPLE) }) { Text(stringResource(R.string.common_sign_in_with_apple)) }
    }
}
