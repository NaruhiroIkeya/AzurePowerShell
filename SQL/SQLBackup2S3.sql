DECLARE @ExecSQL VARCHAR(MAX);
DECLARE @Database VARCHAR(5) = 'SID'
DECLARE @DAYSTR CHAR(12) = FORMAT(GETDATE(),'yyyyMMddHHmm')
DECLARE @BACKUP_FILE VARCHAR(50) = N's3://<endpoint>:<port>/<bucket>/' + @Database + '_FULL_' + @DAYSTR

@ExecSQL = 'BACKUP DATABASE [' + @DATABASE + '] TO URL =' + @BACKUP_FILE + '_01.bak, ' + 
   'URL = ' + @BACKUP_FILE + '_02.bak,' +
   'URL = ' + @BACKUP_FILE + '_03.bak', +
   'URL = ' + @BACKUP_FILE + '_04.bak', +
   'URL = ' + @BACKUP_FILE + '_05.bak', +
   'URL = ' + @BACKUP_FILE + '_06.bak', +
   'URL = ' + @BACKUP_FILE + '_07.bak', +
   'URL = ' + @BACKUP_FILE + '_08.bak', +
   'URL = ' + @BACKUP_FILE + '_09.bak', +
   'URL = ' + @BACKUP_FILE + '_10.bak', +
   'URL = ' + @BACKUP_FILE + '_11.bak', +
   'URL = ' + @BACKUP_FILE + '_12.bak', +
   'URL = ' + @BACKUP_FILE + '_13.bak', +
   'URL = ' + @BACKUP_FILE + '_14.bak', +
   'URL = ' + @BACKUP_FILE + '_15.bak', +
   'URL = ' + @BACKUP_FILE + '_16.bak', +
   'URL = ' + @BACKUP_FILE + '_17.bak', +
   'URL = ' + @BACKUP_FILE + '_18.bak', +
   'URL = ' + @BACKUP_FILE + '_21.bak', +
   'URL = ' + @BACKUP_FILE + '_20.bak', +
   'URL = ' + @BACKUP_FILE + '_21.bak', +
   'URL = ' + @BACKUP_FILE + '_22.bak', +
   'URL = ' + @BACKUP_FILE + '_23.bak', +
   'URL = ' + @BACKUP_FILE + '_24.bak', +
   'URL = ' + @BACKUP_FILE + '_25.bak', +
   'URL = ' + @BACKUP_FILE + '_26.bak', +
   'URL = ' + @BACKUP_FILE + '_27.bak', +
   'URL = ' + @BACKUP_FILE + '_28.bak', +
   'URL = ' + @BACKUP_FILE + '_29.bak', +
   'URL = ' + @BACKUP_FILE + '_30.bak', +
   'URL = ' + @BACKUP_FILE + '_31.bak', +
   'URL = ' + @BACKUP_FILE + '_32.bak', +
   'URL = ' + @BACKUP_FILE + '_33.bak', +
   'URL = ' + @BACKUP_FILE + '_34.bak', +
   'URL = ' + @BACKUP_FILE + '_35.bak', +
   'URL = ' + @BACKUP_FILE + '_36.bak', +
   'URL = ' + @BACKUP_FILE + '_37.bak', +
   'URL = ' + @BACKUP_FILE + '_38.bak', +
   'URL = ' + @BACKUP_FILE + '_39.bak', +
   'URL = ' + @BACKUP_FILE + '_40.bak', +
   'URL = ' + @BACKUP_FILE + '_41.bak', +
   'URL = ' + @BACKUP_FILE + '_42.bak', +
   'URL = ' + @BACKUP_FILE + '_43.bak', +
   'URL = ' + @BACKUP_FILE + '_44.bak', +
   'URL = ' + @BACKUP_FILE + '_45.bak', +
   'URL = ' + @BACKUP_FILE + '_46.bak', +
   'URL = ' + @BACKUP_FILE + '_47.bak', +
   'URL = ' + @BACKUP_FILE + '_48.bak', +
   'URL = ' + @BACKUP_FILE + '_49.bak', +
   'URL = ' + @BACKUP_FILE + '_50.bak', +
   'URL = ' + @BACKUP_FILE + '_51.bak', +
   'URL = ' + @BACKUP_FILE + '_52.bak', +
   'URL = ' + @BACKUP_FILE + '_53.bak', +
   'URL = ' + @BACKUP_FILE + '_54.bak', +
   'URL = ' + @BACKUP_FILE + '_55.bak', +
   'URL = ' + @BACKUP_FILE + '_56.bak', +
   'URL = ' + @BACKUP_FILE + '_57.bak', +
   'URL = ' + @BACKUP_FILE + '_58.bak', +
   'URL = ' + @BACKUP_FILE + '_59.bak', +
   'URL = ' + @BACKUP_FILE + '_60.bak', +
   'URL = ' + @BACKUP_FILE + '_61.bak', +
   'URL = ' + @BACKUP_FILE + '_62.bak', +
   'URL = ' + @BACKUP_FILE + '_63.bak', +
   'URL = ' + @BACKUP_FILE + '_64.bak'  +
'WITH FORMAT, MAXTRANSFERSIZE = 20971520, COMPRESSION, STATS = 10;'

PRINT NCHAR(13) + NCHAR(10) + @ExecSQL
EXEC (@ExecSQL);
