# IdentityCheck
## Identity Value Consumption Check

![spedometer](/images/speedometer.png)

When you use the IDENTITY properties in your tables, you can get the message: 'Arithmetic overflow error converting IDENTITY to data type...' In other words - the free IDs have ended up on the column. Typically, for an INT data type, you exceeded the value of 2 147 483 647.

But no only for INT. Below are all types of data that this may apply to:

Data type | Min | Max | Storage
--------- | --- | --- | -------
Int | -2,147,483,648 | 2,147,483,647 | 4 Bytes
Bigint | -9,223,372,036,854,775,808 | 9,223,372,036,854,775,807 | 8 Bytes
Smallint | -32,768 | 32,767 | 2 Bytes
Tinyint | 0 | 255 | 1 Byte
Decimal(38,0)/Numeric(38,0) | -9999...9999 (max 38 nines)| 9999...9999 (max 38 nines)| 17 Bytes

It's good to know **when** it will happen. The usp_CheckIdentityValue procedure will help you with this.

The following solution is based on the article by Frank Kalis:

http://www.sql-server-performance.com/2010/identity-range-check/

My version of this solution is just to predict when you run out of identifiers.

This is the Polish version of this project:

https://blog.atena.pl/sql-server-administration-przekrecony-licznik

## Parameters of usp_CheckIdentityValue

* **@database** (sysname) - where it put the history of checks (database must be exist) - *default 'tempdb'*

* **@schema** (sysname) - schema name of history (if not exist - it will create it) - *default 'identity'*

* **@LevelAlert** (tinyint) - there is a level (%) after which you will be alarmed that your IDs will end - *default 95 percent*

* **@MonthAlert** (tinyint) - how many months before saturation of identifiers you have to be notified - *default 3 months*

* **@dbmail_profile_name** (nvarchar(200)) - the name of your database mail profile (to send notifications) - *default NULL*

* **@email_recipients** (nvarchar(max)) - who receive emails with report about problematics columns - *default NULL*

## IdentityCheckExceptions table

You use this table if you want to exclude some columns from checking for some reason:

![Report image](/images/IdentityCheckExceptions_table.png)

## Examples of use

* ```Exec [master].[dbo].[usp_CheckIdentityValue] @dbmail_profile_name = 'mail_profile', @email_recipients = 'miros(at)poczta.fm' ```

We assume that we have a DBMail profile called *mail_profile* and the user *miros(at)poczta.fm* will receive a report if at least one of the columns with the IDENTITY property is filled in 95% or 100% has been filled less than 3 months. The data of both tables will be stored in the tempdb database.

User *miros(at)poczta.fm* will receive report like bellow:

![Report image](/images/IdentityValueConsumptionReport.png)

* ```Exec [master].[dbo].[usp_CheckIdentityValue] @database = 'MyDB', @schema = 'RANGE', @LevelAlert = 80, @MonthAlert = 6, @dbmail_profile_name = 'mail_profile', @email_recipients = 'miros(at)poczta.fm' ```

The user *miros(at)poczta.fm* will receive a report if at least one of the columns with the IDENTITY property is already filled in 80% or 100% of the filling has been less than half a year. The MyDB database and the RANGE scheme have been selected as the place for data storage (if there is no such scheme, it will be created).

* ```Exec [master].[dbo].[usp_CheckIdentityValue]```

The report will not be sent, but the status of the columns can be previewed directly by a query:

```
SELECT [id]
      ,[snap_id]
      ,[snap_date]
      ,[database_name]
      ,[schema_name]
      ,[table_name]
      ,[column_name]
      ,[data_type]
      ,[seed_value]
      ,[increment_value]
      ,[precision]
      ,[last_value]
      ,[max_type_value]
      ,[full_type_range]
      ,[buffer]
      ,[identityvalue_consumption_in_percent] * 100.000 AS [identityvalue_consumption_in_percent]
      ,CONVERT(CHAR(10), [expected_date_of_filling], 121) AS [expected_date_of_filling]
  FROM [tempdb].[identity].[IdentityCheck]
  ORDER BY [identityvalue_consumption_in_percent] DESC;
  ```

The following data will appear next to the name of the database, schema, table and column:

![Report image](/images/IdentityValueConsumptionSSMSReport.png)

## Automation

The database administrator needs tools that will run in the background. For this reason, we will not manually run the procedure on our systems, we should only create a SQL Agent job, which will review the IDENTITY columns once a day and send a report if necessary.

Change only the following configuration of job:

```
-- Job configuration --
DECLARE @OwnerLoginName NVARCHAR(200) = N'sa';
DECLARE @EmailOperatorName NVARCHAR(200) = N'MSSQL Admins';
-- usp_CheckIdentityValue configuration  --
DECLARE @dbmail_profile NVARCHAR(200) = N'mail_profile';
DECLARE @email_recipients NVARCHAR(MAX) = N'MSSQLAdmins@domain.com';
DECLARE @DestinationDatabase NVARCHAR(200) = N'tempdb';
DECLARE @DestinationSchema NVARCHAR(200) = N'identity';
DECLARE @LevelAlert NVARCHAR(3) = N'95';
DECLARE @MonthAlert NVARCHAR(3) = N'3';
```

## Installation

Procedure of installation:
1. Download scripts: [latest release zip](/download/IdentityCheck.zip)
2. Install [usp_CheckIdentityValue](/Identity_RANGE.sql) procedure.
3. Edit [Identity_RANGE_CREATE_JOB.sql](/Identity_RANGE_CREATE_JOB.sql) script and run it.
4. And forget about it :)

And suddenly, on a beautiful day you will receive an unexpected email about the ending range of identifiers ... Remember then that you could find out about it during the failure analysis.

