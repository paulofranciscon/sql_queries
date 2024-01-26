Use msdb
GO

DECLARE @check_mountpoint int
SET @check_mountpoint=0 -- default YES

/*
-- ******** Pre-Req  ******
-- If asked, configure this 2 options

exec sp_configure 'show advanced options',1;RECONFIGURE WITH OVERRIDE
exec sp_configure 'Ole Automation Procedures',1;RECONFIGURE WITH OVERRIDE
*/

SET NOCOUNT ON 

PRINT 'Disk Space on Os Drives'
PRINT '========================'
declare @advoptions as sql_variant
declare @oleauto as sql_variant

select @advoptions = value from sys.configurations where name = 'show advanced options'
select @oleauto = value from sys.configurations where name = 'Ole Automation Procedures'

IF @advoptions= 0
BEGIN
 EXEC sp_configure 'show advanced options', 1
 RECONFIGURE WITH OVERRIDE
END
IF @oleauto = 0 
BEGIN
 EXEC sp_configure 'Ole Automation Procedures', 1
 RECONFIGURE WITH OVERRIDE
END

DECLARE @hr int,@fso int,@mbtotal int,@mbfree int,
@SQLDriveSize int,@size float, @drive Varchar(1),@fso_method varchar(255) 

SET @mbtotal = 0 

IF EXISTS (SELECT name FROM tempdb..sysobjects where name like '#dbspace%')
BEGIN
	DROP TABLE tempdb..#dbspace
	DROP TABLE tempdb..#espacodisco
END
ELSE
BEGIN
	CREATE TABLE #dbspace (name sysname, caminho varchar(200),tamanho varchar(10), drive Varchar(30)) 
	CREATE TABLE [#espacodisco] (Drive varchar (10) ,[Total (MB)] Int, [Used (MB)] Int,[Free (MB)] Int, 
	[Free (%)] int, [Used (%)] int, [Ocupado SQL (MB)] Int,[Data] smalldatetime) 
END
-- Used to get disk where database files are placed
Exec sp_MSforeachdb 'Use [?] Insert into #dbspace Select Convert(Varchar(25),db_name())as [Database],Convert(Varchar(60),FileName),Convert(Varchar(8),Size/128)[Size in MB],Convert(Varchar(30),Name) from [?]..sysfiles' 

EXEC @hr = master.dbo.sp_OACreate 'Scripting.FilesystemObject', @fso OUTPUT 

IF OBJECT_ID('tempdb..#space')>0 DROP TABLE #space

CREATE TABLE #space (drive char(1), mbfree int)
INSERT INTO #space EXEC master.dbo.xp_fixeddrives

Declare CheckDrives Cursor For Select drive,mbfree From #space
Open CheckDrives
Fetch Next from CheckDrives into @drive,@mbfree
WHILE(@@FETCH_STATUS=0)
BEGIN
	SET @fso_method = 'Drives("' + @drive + ':").TotalSize'
	SELECT @SQLDriveSize=sum(Convert(Int,tamanho))
	FROM #dbspace WHERE Substring(caminho,1,1)=@drive
	EXEC @hr = sp_OAMethod @fso, @fso_method, @size OUTPUT
	SET @mbtotal =  @size / (1024 * 1024)
	INSERT INTO #espacodisco
	VALUES(@drive+ ':\',@mbtotal,@mbtotal-@mbfree,@mbfree,(100 * round(@mbfree,2) / round(@mbtotal,2)),
	(100-100 * round(@mbfree,2) / round(@mbtotal,2)),@SQLDriveSize, getdate()) 

	FETCH NEXT FROM CheckDrives INTO @drive,@mbfree
END
CLOSE CheckDrives
DEALLOCATE CheckDrives 

IF (OBJECT_ID('_CheckList_Espacodisco') IS NOT NULL)  DROP TABLE _CheckList_Espacodisco 

SELECT Drive, [Total (MB)],[Used (MB)] , [Free (MB)] , [Used (%)] ,[Free (%)],
ISNULL ([Ocupado SQL (MB)],0) AS [Used for DBFiles (MB)]
into dbo._CheckList_Espacodisco
FROM #espacodisco 

SELECT @@SERVERNAME AS 'ServerName',* FROM dbo._CheckList_Espacodisco

DROP TABLE #dbspace
DROP TABLE #space
DROP TABLE #espacodisco 
DROP TABLE _CheckList_Espacodisco

/*

-- Sample result

Drive      Total (MB)  Used (MB)   Free (MB)   Used (%)    Free (%)    Used for DBFiles (MB)
---------- ----------- ----------- ----------- ----------- ----------- ---------------------
C:\        69327       60812       8515        88          12          6540
D:\        139384      211         139173      1           99          0
E:\        139384      124439      14945       90          10          7703
F:\        480004      233276      246728      49          51          0
G:\        473337      299345      173992      64          36          67382

*/

--- Consideeing MountPoints

IF @check_mountpoint=1
BEGIN
declare @svrName varchar(255)
declare @sql varchar(400)
--by default it will take the current server name, we can the set the server name as well
set @svrName = @@SERVERNAME
set @sql = 'powershell.exe -c "Get-WmiObject -ComputerName ' + QUOTENAME(@svrName,'''') + ' -Class Win32_Volume -Filter ''DriveType = 3'' | select name,capacity,freespace | foreach{$_.name+''|''+$_.capacity/1048576+''%''+$_.freespace/1048576+''*''}"'
--creating a temporary table
CREATE TABLE #output
(line varchar(255))
--inserting disk name, total space and free space value in to temporary table
insert #output
EXEC xp_cmdshell @sql
--script to retrieve the values in MB from PS Script output

select rtrim(ltrim(SUBSTRING(line,1,CHARINDEX('|',line) -1))) as drivename
      ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('|',line)+1,
      (CHARINDEX('%',line) -1)-CHARINDEX('|',line)) )) as Float),0) as 'capacity(MB)'
      ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('%',line)+1,
      (CHARINDEX('*',line) -1)-CHARINDEX('%',line)) )) as Float),0) as 'freespace(MB)'
INTO    #output2 
from #output
where line like '[A-Z][:]%'
order by drivename

SELECT *,ROUND((100-100 * round([freespace(MB)],2) / round([capacity(MB)],2)),0)As [Used%],
ROUND((100 * round([freespace(MB)],2) / round([capacity(MB)],2)),0) as [Free%] from #output2

drop table #output
drop table #output2
END