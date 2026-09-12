# Classes and roster import

`ClassesScreen` lists owned classes and classes represented in saved schedules.
`RosterImportScreen` reads XLSX/ODS, previews a sheet/class group and matches semester + class + subject.
`getRoster` and `importRoster` are scoped server actions; generic sheet writes remain prohibited.
See `docs/ROSTER_IMPORT.md` for the workflow, backend deployment and duplicate handling.
