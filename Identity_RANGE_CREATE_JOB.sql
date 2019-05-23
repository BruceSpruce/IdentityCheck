/*
    CREATE JOB
    CHANGE THE PARAMETERS BELLOW
*/
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
-----------============================================================-------------
DECLARE @UserName NVARCHAR(200) =
        (
            SELECT SUSER_NAME()
        );
DECLARE @CreateDate CHAR(10) =
        (
            SELECT CONVERT(CHAR(10), GETDATE(), 102)
        );
DECLARE @JobDescription NVARCHAR(MAX) = N'Check Identity Consumption procedure - ' + @UserName + ' ' + @CreateDate;
DECLARE @SQLCommand NVARCHAR(MAX)
    = N'EXEC master..usp_CheckIdentityValue @dbmail_profile_name = ''' + @dbmail_profile + ''',@email_recipients = '''
      + @email_recipients + ''', @database = N''' + @DestinationDatabase + ''', @schema = ''' + @DestinationSchema
      + ''', @LevelAlert = ''' + @LevelAlert + ''', @MonthAlert = ' + @MonthAlert;
-----------============================================================-------------

USE [msdb];


BEGIN TRANSACTION;
DECLARE @ReturnCode INT;
SELECT @ReturnCode = 0;

IF NOT EXISTS
(
    SELECT name
    FROM msdb.dbo.syscategories
    WHERE name = N'[Uncategorized (Local)]'
          AND category_class = 1
)
BEGIN
    EXEC @ReturnCode = msdb.dbo.sp_add_category @class = N'JOB',
                                                @type = N'LOCAL',
                                                @name = N'[Database Maintenance]';
    IF (@@ERROR <> 0 OR @ReturnCode <> 0)
        GOTO QuitWithRollback;

END;

DECLARE @jobId BINARY(16);
EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'__CHECK_IDENTITY_CONSUMPTION__',
                                       @enabled = 1,
                                       @notify_level_eventlog = 0,
                                       @notify_level_email = 2,
                                       @notify_level_netsend = 0,
                                       @notify_level_page = 0,
                                       @delete_level = 0,
                                       @description = @JobDescription,
                                       @category_name = N'[Uncategorized (Local)]',
                                       @owner_login_name = @OwnerLoginName,
                                       @notify_email_operator_name = @EmailOperatorName,
                                       @job_id = @jobId OUTPUT;
IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;
/****** Object:  Step [_IdentityCheck_]    Script Date: 01.08.2018 15:43:35 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId,
                                           @step_name = N'_IdentityCheck_',
                                           @step_id = 1,
                                           @cmdexec_success_code = 0,
                                           @on_success_action = 1,
                                           @on_success_step_id = 0,
                                           @on_fail_action = 2,
                                           @on_fail_step_id = 0,
                                           @retry_attempts = 0,
                                           @retry_interval = 0,
                                           @os_run_priority = 0,
                                           @subsystem = N'TSQL',
                                           @command = @SQLCommand,
                                           @database_name = N'master',
                                           @flags = 0;
IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId,
                                          @start_step_id = 1;
IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id = @jobId,
                                               @name = N'Daily at 00:00',
                                               @enabled = 1,
                                               @freq_type = 4,
                                               @freq_interval = 1,
                                               @freq_subday_type = 1,
                                               @freq_subday_interval = 0,
                                               @freq_relative_interval = 0,
                                               @freq_recurrence_factor = 0,
                                               @active_start_date = 20180510,
                                               @active_end_date = 99991231,
                                               @active_start_time = 0,
                                               @active_end_time = 235959;
IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId,
                                             @server_name = N'(local)';
IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;
COMMIT TRANSACTION;
GOTO EndSave;
QuitWithRollback:
IF (@@TRANCOUNT > 0)
    ROLLBACK TRANSACTION;
EndSave:
GO


