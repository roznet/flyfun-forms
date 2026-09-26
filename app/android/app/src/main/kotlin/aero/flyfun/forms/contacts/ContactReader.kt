package aero.flyfun.forms.contacts

import aero.flyfun.forms.logic.ContactImport
import aero.flyfun.forms.logic.ImportedContact
import android.content.Context
import android.net.Uri
import android.util.Log
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Event
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.CommonDataKinds.StructuredName
import android.provider.ContactsContract.CommonDataKinds.StructuredPostal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Reads the one contact the system picker handed back.
 *
 * No READ_CONTACTS: `ActivityResultContracts.PickContact` grants read access
 * to the picked contact only, and its entity rows (name parts, phones,
 * e-mails, addresses, birthday) are read through that contact's own URI.
 * Anything the provider will not give is left empty rather than failing: the
 * display name alone still makes a person.
 */
object ContactReader {

    suspend fun read(context: Context, contactUri: Uri): ImportedContact? = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val displayName = runCatching {
            resolver.query(contactUri, arrayOf(ContactsContract.Contacts.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        }.getOrNull()

        var first: String? = null
        var last: String? = null
        val phones = mutableListOf<String>()
        val emails = mutableListOf<String>()
        val addresses = mutableListOf<String>()
        var birthday: String? = null

        runCatching {
            val entities = Uri.withAppendedPath(contactUri, ContactsContract.Contacts.Entity.CONTENT_DIRECTORY)
            val columns = arrayOf(
                ContactsContract.Contacts.Entity.MIMETYPE,
                ContactsContract.Contacts.Entity.DATA1,
                ContactsContract.Contacts.Entity.DATA2,
                ContactsContract.Contacts.Entity.DATA3,
                ContactsContract.Contacts.Entity.DATA4,
                ContactsContract.Contacts.Entity.DATA7,
                ContactsContract.Contacts.Entity.DATA9,
                ContactsContract.Contacts.Entity.DATA10,
            )
            resolver.query(entities, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    fun text(i: Int) = c.getString(i)?.trim()?.takeIf { it.isNotEmpty() }
                    when (c.getString(0)) {
                        // DATA2 given name, DATA3 family name.
                        StructuredName.CONTENT_ITEM_TYPE -> {
                            first = first ?: text(2)
                            last = last ?: text(3)
                        }
                        Phone.CONTENT_ITEM_TYPE -> text(1)?.let { if (it !in phones) phones += it }
                        Email.CONTENT_ITEM_TYPE -> text(1)?.let { if (it !in emails) emails += it }
                        // DATA4 street, DATA7 city, DATA9 postcode, DATA10 country.
                        StructuredPostal.CONTENT_ITEM_TYPE ->
                            ContactImport.addressLine(text(4), text(5), text(6), text(7))?.let { addresses += it }
                        // DATA1 the date, DATA2 its type.
                        Event.CONTENT_ITEM_TYPE ->
                            if (c.getInt(2) == Event.TYPE_BIRTHDAY) birthday = birthday ?: text(1)
                    }
                }
            }
        }.onFailure {
            // Only the name comes through when the picker's grant does not reach
            // the contact's data rows; say so rather than lose them silently.
            Log.w("ContactReader", "Contact details unreadable, importing the name only", it)
        }

        if (first == null && last == null) {
            // Only the display name came through: "Jane van Dijk" is Jane + van Dijk.
            val words = displayName?.trim()?.split(Regex("\\s+")).orEmpty().filter { it.isNotEmpty() }
            if (words.isEmpty()) return@withContext null
            first = if (words.size > 1) words.first() else ""
            last = if (words.size > 1) words.drop(1).joinToString(" ") else words.first()
        }
        ImportedContact(
            firstName = first.orEmpty(),
            lastName = last.orEmpty(),
            phones = phones,
            emails = emails,
            addresses = addresses,
            dateOfBirth = ContactImport.parseBirthday(birthday),
        )
    }
}
