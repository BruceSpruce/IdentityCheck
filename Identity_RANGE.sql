USE [master]
GO

IF NOT EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE type = 'P'
          AND object_id = OBJECT_ID('dbo.usp_CheckIdentityValue')
)
    EXEC ('CREATE PROCEDURE [dbo].[usp_CheckIdentityValue] AS BEGIN SELECT 1; END');
GO

ALTER PROCEDURE [dbo].[usp_CheckIdentityValue]
	@database sysname = N'tempdb',
	@schema sysname = N'identity',
	@LevelAlert TINYINT = 95,
	@MonthAlert TINYINT = 3,
	@dbmail_profile_name NVARCHAR(200) = NULL,
	@email_recipients NVARCHAR(MAX) = NULL	
AS
------------------------------------------
---- Check Identity Value Consumption ----
---------- Version 1.01 (2019) -----------
------------------------------------------
---- Examples:
---- EXEC master..usp_CheckIdentityValue @dbmail_profile_name = 'mail_profile',@email_recipients = 'miros@poczta.fm'
BEGIN
		
	---- VARIABLES ----
	DECLARE @subject NVARCHAR(200) = '[' + @@SERVERNAME + '] IDENTITY VALUE CONSUMPTION REPORT. DATE: ' + CONVERT(CHAR(19), SYSDATETIME(), 121);
	DECLARE @version NVARCHAR(200) = 'Identity Value Consumption REPORT v.1.01 (' + CAST (YEAR(SYSDATETIME()) AS CHAR(4)) + ')';
	DECLARE @html_body NVARCHAR(MAX);
	DECLARE @ErrorMessage NVARCHAR(4000);  
    DECLARE @ErrorSeverity INT;  
    DECLARE @ErrorState INT;  
	DECLARE @RowCount INT;
    DECLARE @SendEmail BIT = 1;

    ---- Check e-mail parameters ----
	IF (ISNULL(@dbmail_profile_name, '') = '')
		SET @SendEmail = 0;
	
	IF (ISNULL(@email_recipients, '') = '')
	    SET @SendEmail = 0;
	
    ---- Create and filling TypeRange Table ----
	SET NOCOUNT ON;

	DECLARE @SQLCommand NVARCHAR(MAX) = N'
	USE [' + @database + '];

	IF NOT EXISTS ( SELECT  1
					FROM    sys.schemas
					WHERE   name = N''' + @schema + ''' ) 
		EXEC(''CREATE SCHEMA [' + @schema + ']'');

	IF NOT EXISTS ( SELECT 1
					FROM sys.tables t
					JOIN sys.schemas s
					ON t.schema_id = s.schema_id
					WHERE s.name = ''' + @schema + ''' AND
						  t.name = ''TypeRange'')
	BEGIN
		CREATE TABLE [' + @schema + '].[TypeRange]
		(
			ID INT IDENTITY(1,1) CONSTRAINT PK_ID_TypeRange PRIMARY KEY CLUSTERED,
			name VARCHAR(20),
			MaxValue NUMERIC(38,0) NOT NULL,
			MinValue NUMERIC(38,0) NOT NULL,
			Precision TINYINT NULL
		);

		INSERT INTO [' + @schema + '].[TypeRange]
		SELECT
			''bigint'' AS [name],
			9223372036854775807 AS MaxValue,
			-9223372036854775808 AS MinValue,
			19 AS Precision
		UNION ALL
		SELECT
			''int'',
			2147483647,
			-2147483648,
			10 AS Precision
		UNION ALL
		SELECT
			''smallint'',
			32767,
			-32768,
			5 AS Precision
		UNION ALL
		SELECT
			''tinyint'',
			255,
			0,
			3 AS Precision

		-- DECIMAL/NUMERIC --
		DECLARE @SIZE TINYINT = 1
		DECLARE @CMD VARCHAR(MAX) = '''';
		DECLARE @VALUE NUMERIC(38, 0) = 0;

		WHILE (@SIZE <= 38)
		BEGIN
			SET @VALUE = -CAST(REPLICATE(''9'', @SIZE) AS NUMERIC(38, 0));
			SET @CMD
				= ''INSERT INTO [' + @schema + '].[TypeRange] SELECT ''''numeric'''' AS [name], '' + CAST(ABS(@VALUE) AS VARCHAR(39))
				  + '' AS MaxValue, '' + CAST(@VALUE AS VARCHAR(39)) + '' AS MinValue, '' + CAST(@SIZE AS VARCHAR)
				  + '' AS Precision;'';
			EXEC (@CMD);
			SET @CMD
				= ''INSERT INTO [' + @schema + '].[TypeRange] SELECT ''''decimal'''' AS [name], '' + CAST(ABS(@VALUE) AS VARCHAR(39))
				  + '' AS MaxValue, '' + CAST(@VALUE AS VARCHAR(39)) + '' AS MinValue, '' + CAST(@SIZE AS VARCHAR)
				  + '' AS Precision;'';
			EXEC (@CMD);
			SET @SIZE += 1;
		END;
	END;';
	BEGIN TRY
		EXECUTE(@SQLCommand);
	END TRY
	BEGIN CATCH
		SELECT   
			@ErrorMessage = ERROR_MESSAGE(),  
			@ErrorSeverity = ERROR_SEVERITY(),  
			@ErrorState = ERROR_STATE();
		PRINT 'Command: ' + @SQLCommand;
		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
		RETURN 1;
	END CATCH

	---- Create IdentityCheck Table ----
	SET @SQLCommand = N'
	USE [' + @database + '];

	IF NOT EXISTS ( SELECT 1
					FROM sys.tables t
					JOIN sys.schemas s
					ON t.schema_id = s.schema_id
					WHERE s.name = ''' + @schema + ''' AND
						  t.name = ''IdentityCheck'')
	CREATE TABLE [' + @schema + '].[IdentityCheck](
		[id] [int] IDENTITY (1,1) CONSTRAINT [PK_ID_IdentityCheck] PRIMARY KEY CLUSTERED,
		[snap_id] [int] NOT NULL,
		[snap_date] [datetime2] NOT NULL,
		[database_name] [sysname] NOT NULL,
		[schema_name] [nvarchar](128) NULL,
		[table_name] [sysname] NOT NULL,
		[column_name] [sysname] NULL,
		[data_type] [sysname] NOT NULL,
		[seed_value] [numeric](38, 0) NULL,
		[increment_value] [sql_variant] NULL,
		[Precision] [tinyint] NOT NULL,
		[last_value] [numeric](38, 0) NULL,
		[max_type_value] [numeric](38, 0) NOT NULL,
		[full_type_range] [numeric](38, 0) NULL,
		[buffer] [numeric](38, 0) NULL,
		[identityvalue_consumption_in_percent] [numeric](38, 6) NULL,
		[expected_date_of_filling] [datetime2] NULL
	) ON [PRIMARY]';
	BEGIN TRY
		EXECUTE(@SQLCommand);
	END TRY
	BEGIN CATCH
		SELECT   
			@ErrorMessage = ERROR_MESSAGE(),  
			@ErrorSeverity = ERROR_SEVERITY(),  
			@ErrorState = ERROR_STATE();
		PRINT 'Command: ' + @SQLCommand;
		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
		RETURN 1;
	END CATCH

    ---- Create IdentityCheckExceptions Table ----
	SET @SQLCommand = N'
	USE [' + @database + '];

	IF NOT EXISTS ( SELECT 1
					FROM sys.tables t
					JOIN sys.schemas s
					ON t.schema_id = s.schema_id
					WHERE s.name = ''' + @schema + ''' AND
						  t.name = ''IdentityCheckExceptions'')
	CREATE TABLE [' + @schema + '].[IdentityCheckExceptions](
		[id] [int] IDENTITY (1,1) CONSTRAINT [PK_ID_IdentityCheckExceptions] PRIMARY KEY CLUSTERED,
		[database_name] [sysname] NOT NULL,
		[schema_name] [nvarchar](128) NULL,
		[table_name] [sysname] NOT NULL,
		[column_name] [sysname] NULL
	) ON [PRIMARY]';
	BEGIN TRY
		EXECUTE(@SQLCommand);
	END TRY
	BEGIN CATCH
		SELECT   
			@ErrorMessage = ERROR_MESSAGE(),  
			@ErrorSeverity = ERROR_SEVERITY(),  
			@ErrorState = ERROR_STATE();
		PRINT 'Command: ' + @SQLCommand;
		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
		RETURN 1;
	END CATCH


	---- PROCEDURE ----
	---- GET LAST SNAP_ID ----
	DECLARE @Snap_id INT;
	DECLARE @ParamDef NVARCHAR(50);

	SET @SQLCommand = N'
					  SELECT @Snap_id_OUT = CASE
						WHEN ((SELECT MAX(snap_id) FROM [' + @database + '].[' + @schema + '].[IdentityCheck]) IS NULL)
						THEN 1
						ELSE (SELECT MAX(snap_id) + 1 FROM [' + @database + '].[' + @schema + '].[IdentityCheck])
					  END;';

	SET @ParamDef = N'@Snap_id_OUT INT OUTPUT'

	EXEC sys.sp_executesql @SQLCommand, @ParamDef, @Snap_id_OUT = @Snap_id OUTPUT;

	DECLARE @name SYSNAME
	DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state = 0
          AND user_access = 0
          AND
          (
              source_database_id IS NULL
              AND is_read_only = 0
          );

	OPEN db_cursor  
	FETCH NEXT FROM db_cursor INTO @name 

	WHILE @@FETCH_STATUS = 0  
	BEGIN  
			---- Get all columns with identity properties ----
			SET @SQLCommand = N'USE [' + @name + '];
			;WITH IdentBuffer AS (
			SELECT ' + CAST(@Snap_id AS VARCHAR(39)) + ' AS [snap_id],
				SYSDATETIME() AS [snap_date],
				DB_NAME() AS [database_name], 
				OBJECT_SCHEMA_NAME(IC.object_id) AS [schema_name],
				O.name AS table_name,
				IC.name AS column_name,
				T.name AS data_type,
				TR.Precision AS Precision,
				CAST(IC.seed_value AS decimal(38, 0)) AS seed_value,
				IC.increment_value,
				CAST(IC.last_value AS decimal(38, 0)) AS last_value,
				CAST(TR.MaxValue AS decimal(38, 0)) -
					CAST(ISNULL(IC.last_value, 0) AS decimal(38, 0)) AS [buffer],
				CAST(CASE
						WHEN seed_value < 0
						THEN TR.MaxValue - TR.MinValue
						ELSE TR.MaxValue
					END AS decimal(38, 0)) AS full_type_range,
				TR.MaxValue AS max_type_value,
				NULL AS [expected_date_of_filling]
			FROM
				sys.identity_columns IC WITH (NOLOCK)
				JOIN
				sys.types T WITH (NOLOCK) ON IC.system_type_id = T.system_type_id
				JOIN
				sys.objects O WITH (NOLOCK) ON IC.object_id = O.object_id
				JOIN
				[' + @database + '].[' + @schema + '].[TypeRange] TR ON T.[name] COLLATE DATABASE_DEFAULT = TR.[name] COLLATE DATABASE_DEFAULT AND IC.[Precision] = TR.[Precision]
			WHERE
				O.is_ms_shipped = 0)
			INSERT INTO [' + @database + '].[' + @schema + '].[IdentityCheck]
			SELECT
				IdentBuffer.[snap_id],
				IdentBuffer.[snap_date],
				IdentBuffer.[database_name],
				IdentBuffer.[schema_name],
				IdentBuffer.[table_name],
				IdentBuffer.[column_name],
				IdentBuffer.[data_type],
				IdentBuffer.[seed_value],
				IdentBuffer.[increment_value],
				IdentBuffer.[Precision],
				IdentBuffer.[last_value],
				IdentBuffer.[max_type_value],
				IdentBuffer.[full_type_range],
				CASE
					WHEN IdentBuffer.[increment_value] < 0
					THEN ABS (- IdentBuffer.[full_type_range] - IdentBuffer.[last_value])
					ELSE IdentBuffer.[buffer]
				END AS [buffer],
				CASE
					WHEN IdentBuffer.[increment_value] < 0
					THEN ABS(-IdentBuffer.[seed_value] +
					  IdentBuffer.[last_value]) / IdentBuffer.[full_type_range]
					ELSE (IdentBuffer.[last_value]) / IdentBuffer.[full_type_range]
				END AS [identityvalue_consumption_in_percent],
				IdentBuffer.[expected_date_of_filling]
			FROM
				IdentBuffer;
            
            -- DELETE EXCEPTIONS
            DELETE [IC] FROM [' + @database + '].[' + @schema + '].[IdentityCheck] AS [IC]
            JOIN [' + @database + '].[' + @schema + '].[IdentityCheckExceptions] AS [ICE]
                ON [IC].[database_name] = [ICE].[database_name]
                AND [IC].[schema_name] = [ICE].[schema_name]
                AND [IC].[table_name] = [ICE].[table_name]
                AND [IC].[column_name] = [ICE].[column_name] 
            ';
			BEGIN TRY
				EXECUTE(@SQLCommand);
			END TRY
			BEGIN CATCH
			SELECT   
				@ErrorMessage = ERROR_MESSAGE(),  
				@ErrorSeverity = ERROR_SEVERITY(),  
				@ErrorState = ERROR_STATE();
				PRINT 'Command: ' + @SQLCommand;
				RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
				RETURN 1;
			END CATCH
			
			---- Calculate expected_date_of_filling ----
			SET @SQLCommand = N'USE [' + @name + '];
			-- Count Of Columns
			DECLARE @CntOfCol INT;
			SELECT @CntOfCol = COUNT(*)
			FROM [' + @database + '].[' + @schema + '].[IdentityCheck]
			WHERE snap_id = ' + CAST(@Snap_id AS VARCHAR(39)) + ';
			-- MAX ID
			DECLARE @MaxID INT;
			SELECT @MaxID = MAX(id)
			FROM [' + @database + '].[' + @schema + '].[IdentityCheck];
		
			WHILE (@CntOfCol > 0)
			BEGIN
				;WITH I1
				 AS (SELECT *
					 FROM [' + @database + '].[' + @schema + '].[IdentityCheck]
					 WHERE id = @MaxID)
				UPDATE I1 
					 SET expected_date_of_filling = 
					   CASE 
							WHEN DATEDIFF(MINUTE, R.snap_date, I.snap_date) < 60
							THEN CAST (''9999-12-31 23:59:59.9999999'' AS DATETIME2)
							   ELSE CASE
							   WHEN CAST ((R.max_type_value - I.last_value)/(ABS(IIF(ISNULL(R.last_value, 1) - ISNULL(I.last_value, 1) = 0, 1, ISNULL(R.last_value, 1) - ISNULL(I.last_value, 1)))/IIF(DATEDIFF(HOUR, R.snap_date, I.snap_date) = 0, 1, DATEDIFF(HOUR, R.snap_date, I.snap_date))) AS NUMERIC(38,0)) > 60000000
							   THEN CAST (''9999-12-31 23:59:59.9999999'' AS DATETIME2)
							   ELSE CASE 
									WHEN (ISNULL(I.last_value, 1) - ISNULL(R.last_value, 1)) = 0
									THEN CAST (''9999-12-31 23:59:59.9999999'' AS DATETIME2)
									ELSE CASE 
										 WHEN (DATEADD(HOUR, CAST ((R.max_type_value - I.last_value)/(ABS(IIF(ISNULL(R.last_value, 1) - ISNULL(I.last_value, 1) = 0, 1, ISNULL(R.last_value, 1) - ISNULL(I.last_value, 1)))/IIF(DATEDIFF(HOUR, R.snap_date, I.snap_date) = 0, 1, DATEDIFF(HOUR, R.snap_date, I.snap_date))) AS NUMERIC(38,0)), SYSDATETIME())) IS NULL
										 THEN CAST (''9999-12-31 23:59:59.9999999'' AS DATETIME2)
										 ELSE DATEADD(HOUR, CAST ((R.max_type_value - I.last_value)/(ABS(IIF(ISNULL(R.last_value, 1) - ISNULL(I.last_value, 1) = 0, 1, ISNULL(R.last_value, 1) - ISNULL(I.last_value, 1)))/IIF(DATEDIFF(HOUR, R.snap_date, I.snap_date) = 0, 1, DATEDIFF(HOUR, R.snap_date, I.snap_date))) AS NUMERIC(38,0)), SYSDATETIME())
									END
							   END
							END
					   END
				FROM I1 I
					LEFT JOIN [' + @database + '].[' + @schema + '].[IdentityCheck] R
						ON I.database_name COLLATE DATABASE_DEFAULT = R.database_name COLLATE DATABASE_DEFAULT
						   AND I.schema_name COLLATE DATABASE_DEFAULT = R.schema_name COLLATE DATABASE_DEFAULT
						   AND I.table_name COLLATE DATABASE_DEFAULT = R.table_name COLLATE DATABASE_DEFAULT
						   AND I.column_name COLLATE DATABASE_DEFAULT = R.column_name COLLATE DATABASE_DEFAULT
						   AND I.Precision = R.Precision
						   AND I.snap_id <> R.snap_id;

				SET @CntOfCol -= 1;
				SET @MaxID -= 1;
			END;';
			BEGIN TRY
				EXECUTE(@SQLCommand);
			END TRY
			BEGIN CATCH
				SELECT   
					@ErrorMessage = ERROR_MESSAGE(),  
					@ErrorSeverity = ERROR_SEVERITY(),  
					@ErrorState = ERROR_STATE();
				PRINT 'Command: ' + @SQLCommand;
				RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
				RETURN 1;
			END CATCH
					
		  FETCH NEXT FROM db_cursor INTO @name 
	END 

	CLOSE db_cursor  
	DEALLOCATE db_cursor 

	---- Delete old snaps ----
	SET @SQLCommand = N'DELETE FROM [' + @database + '].[' + @schema + '].[IdentityCheck] WHERE snap_id < (SELECT MAX(snap_id) FROM [' + @database + '].[' + @schema + '].[IdentityCheck]);';
	BEGIN TRY
		EXECUTE(@SQLCommand);
	END TRY
	BEGIN CATCH
		SELECT   
			@ErrorMessage = ERROR_MESSAGE(),  
			@ErrorSeverity = ERROR_SEVERITY(),  
			@ErrorState = ERROR_STATE();
		PRINT 'Command: ' + @SQLCommand;
		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
		RETURN 1;
	END CATCH

	---- REPORTS ----
	IF OBJECT_ID('tempdb..##IdentityCheckReport') IS NOT NULL
		DROP TABLE ##IdentityCheckReport

	SET @SQLCommand = N'SELECT [database_name]
							  ,[schema_name]
							  ,[table_name]
							  ,[column_name]
							  ,[data_type]
							  ,[increment_value]
							  ,[Precision]
							  ,[last_value]
							  ,[max_type_value]
							  ,[buffer]
							  ,[identityvalue_consumption_in_percent] * 100.0000 AS [identityvalue_consumption_in_percent]
							  ,CONVERT(CHAR(10), [expected_date_of_filling], 121) AS [expected_date_of_filling]
						  INTO ##IdentityCheckReport
						  FROM [' + @database + '].[' + @schema + '].[IdentityCheck]
						  WHERE [identityvalue_consumption_in_percent] * 100.0000 >= ' + CAST(@LevelAlert AS VARCHAR(3)) + '
						  OR [expected_date_of_filling] <= ''' + (SELECT CONVERT(CHAR(10), DATEADD(MONTH, @MonthAlert, SYSDATETIME()))) + '''';
	BEGIN TRY
		EXECUTE(@SQLCommand);
		SET @RowCount = @@ROWCOUNT;
	END TRY
	BEGIN CATCH
		SELECT   
			@ErrorMessage = ERROR_MESSAGE(),  
			@ErrorSeverity = ERROR_SEVERITY(),  
			@ErrorState = ERROR_STATE();
		PRINT 'Command: ' + @SQLCommand;
		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
		RETURN 1;
	END CATCH

	---- REPORT PREPARE ----
	IF (@RowCount <> 0 AND @SendEmail = 1)
	BEGIN
		SET @html_body = '<html><head>' +
						 '<style>' +
						 'td {border: solid black 1px;padding-left:5px;padding-right:5px;padding-top:1px;padding-bottom:1px;font-size:11pt;}' +
				 		 '</style>' +
						 '</head>' +
						 '<body><table cellpadding=0 cellspacing=0 border=0>' +
						 '<tr bgcolor=#ffd966>' +
						 '<td align=center><b>Pos</b></td>' +
						 '<td align=center><b>Server Name</b></td>' +
						 '<td align=center><b>Database Name</b></td>' +
						 '<td align=center><b>Schema Name</b></td>' +
						 '<td align=center><b>Table Name</b></td>' +
						 '<td align=center><b>Column Name</b></td>' +
						 '<td align=center><b>Data Type</b></td>' +
						 '<td align=center><b>Increment Value</b></td>' + 
						 '<td align=center><b>Precisiom</b></td>' + 
						 '<td align=center><b>Last Value Value</b></td>' + 
						 '<td align=center><b>Max Type Value</b></td>' + 
						 '<td align=center><b>Buffer</b></td>' + 
						 '<td align=center><b>Identity Value Consumption (%)</b></td>' + 
						 '<td align=center><b>Expected Date Of Filling</b></td></tr>';
	
		SET @html_body += 
		(SELECT
			ROW_NUMBER() OVER(ORDER BY identityvalue_consumption_in_percent DESC) AS [TD align=right],
			@@SERVERNAME AS [TD align=center],
			database_name AS [TD align=center],
			schema_name AS [TD align=center],
			table_name AS [TD align=center],
			column_name AS [TD align=center],
			data_type AS [TD align=center],
			increment_value AS [TD align=right],
			Precision AS [TD align=right],
			last_value AS [TD align=right],
			max_type_value AS [TD align=right],
			buffer AS [TD align=right],
			FORMAT(identityvalue_consumption_in_percent, '###.0000') AS [TD align=right],
			IIF(expected_date_of_filling='9999-12-31', 'probably never', expected_date_of_filling) AS [TD align=center]
		FROM ##IdentityCheckReport 
		ORDER BY identityvalue_consumption_in_percent DESC
		FOR XML RAW('TR'), ELEMENTS);

		---- Replace the entity codes and row numbers ----
		SET @html_body = REPLACE(@html_body, '_x0020_', space(1));
		SET @html_body = REPLACE(@html_body, '_x003D_', '=');

		---- close html code ----
		SET @html_body += '</table></br>' + @version + '</br></body></html>'

		---- send e-mail ----
		EXEC msdb.dbo.sp_send_dbmail
					@profile_name = @dbmail_profile_name,
					@recipients = @email_recipients,
					@body =  @html_body,
					@subject = @subject,
					@body_format = 'HTML';
	END
END;
