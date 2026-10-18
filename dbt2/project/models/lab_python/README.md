Python models run on the Spark work group. They read tables: Spark cannot read Athena views
(Presto SQL in Glue), which fails with "Can not create a Path from an empty string".
