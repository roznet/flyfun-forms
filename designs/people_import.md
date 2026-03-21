# People CSV Import

Import crew and passengers from a CSV file into FlyFun Forms.

## Quick start

1. Open the **People** tab
2. Tap **Import CSV**
3. Select your `.csv` file

Duplicates (same first name + last name + date of birth) are automatically skipped.

## CSV format

Standard comma-separated file with a header row. Column order does not matter. Column names are case-insensitive.

### Required columns

| Column       | Description       |
|--------------|-------------------|
| First Name   | Given name(s)     |
| Last Name    | Family name       |

### Optional columns

| Column            | Format       | Description                                      |
|-------------------|--------------|--------------------------------------------------|
| Gender            | Text         | e.g. Male, Female, M, F                          |
| DoB               | YYYY-MM-DD   | Date of birth                                    |
| Nationality       | ISO alpha-3  | e.g. GBR, FRA, USA, NLD                          |
| Doc Type          | Text         | e.g. Passport, Identity card (defaults to Passport) |
| Doc Number        | Text         | Passport or ID number                            |
| Doc Expiry        | YYYY-MM-DD   | Document expiry date                             |
| Doc Issuing State | ISO alpha-3  | Country that issued the document                 |
| Type              | Text         | `Crew` marks the person as usual crew; anything else (or blank) = passenger |

### Notes

- Quoted fields are supported: `"Kowalski, Jr."` works correctly.
- Rows where both First Name and Last Name are empty are skipped.
- Invalid or missing dates are ignored (no error, the field is left blank).
- A travel document is only created when Doc Number is provided.
- Any extra columns (e.g. Id, Notes) are silently ignored.

## Example

```csv
First Name,Last Name,Gender,DoB,Nationality,Doc Type,Doc Number,Doc Expiry,Doc Issuing State,Type
Jane,Smith,Female,1985-03-22,GBR,Passport,526464165,2030-05-29,GBR,Crew
John,Doe,Male,1990-11-07,USA,Passport,A32358523,2033-10-30,USA,Passenger
```
