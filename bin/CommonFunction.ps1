<################################################################################
## Copyright(c) 2019 BeeX Inc. All rights reserved.
## @auther#Yasutoshi Tamura
##
## @name:CommonFunction.ps1
## @summary:���ʊ֐����W���[��
##          
## @since:2019/07/
## @version:1.0
## @see:
## @parameter
##  
##
## @return:None
################################################################################>

<#
    .SYNOPSIS
    ���ʊ֐����W���[��
#>

## XML�t�@�C���̓Ǎ����s������
function AzureProc {
    $obj = New-Object PSObject -Property @{
        xmlDir = "";
        xmlName = "AzureVMInfo.xml";
        subscriptionName = ""
        subscriptid = ""
        xmlFile = ""
        resourceGroup = ""
        vmsize = ""
        drVmName = ""
        drResourceGroup = ""
        drStorageAccount = ""
        drContainer = ""
        drLocation = ""
        drDiskAccounttype = ""
        drVnet = ""
        drSubnet = ""
        drIPaddress = ""
        drVmSize = ""
    };

    $obj | Add-Member -MemberType ScriptMethod -Name load -Value {
        param(
            [string]$xmlDir,
            [string]$xmlName = "AzureVMInfo.xml")

        $this.xmlDir = $xmlDir
        $this.xmlName = $xmlName
        $xmlPath = Join-Path -Path $this.xmlDir -ChildPath $this.xmlName

        if (!( Test-Path $xmlPath)) {
            return 1
        }

        $this.xmlFile = [xml](Get-Content $xmlPath)

        return 0

    };

    ## Azure�T�u�X�N���v�V�������Z�b�g����
    $obj | Add-Member -MemberType ScriptMethod -Name setSubscription -Value {
        param(
            [string]$vmname
        )

        foreach($subscript in $this.xmlFile.config.vminfo.subscription) {
            $vm = $subscript.vm | Where-Object {$_.name -eq $vmname}
            
            if (!($vm)) {
                continue
            }

            Select-AzSubscription -SubscriptionId $subscript.id | Out-Null
            
            $this.subscriptionName = (Get-AzSubscription -SubscriptionId $subscript.id).Name
            $this.subscriptid = $subscript.id

            return 0
        }

        return 1
    };

    ## Azure���O�C��������
    $obj | Add-Member -MemberType ScriptMethod -Name AzureLogin -Value {
        
        ## ��`�t�@�C�����烍�O�C�������擾����
        $appId = $this.getParam("config/common/azurelogin/appid")
        $tenantId = $this.getParam("config/common/azurelogin/tenant")
        $pwdFile = $this.getParam("config/common/azurelogin/pwdfile")

        $pwdPath = Join-Path $this.xmlDir -ChildPath $pwdFile

        if (!(Test-Path $pwdPath)){
            return 1
        }

        $secpwd = Get-Content $pwdPath | ConvertTo-SecureString -AsPlainText -Force
        $mycreds = New-Object System.Management.Automation.PSCredential ($appId, $secpwd)

        ## ���O�C������
        Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $mycreds -WarningAction Ignore | Out-Null

        $subscriptionlist = Get-AzSubscription
        if(!$subscriptionlist){
            return 1
        }

        return 0
    };


    ## XML�̃p�����[�^���擾����
    $obj | Add-Member -MemberType ScriptMethod -Name getParam -Value {
        param([string]$node)

        return $this.xmlFile.SelectNodes($node)."#text"
    };

    ## VM�̏����v���p�e�B�ɃZ�b�g����
    $obj | Add-Member -MemberType ScriptMethod -Name setVMInfo -Value {
        param(
            [string]$vmname
        )

        $this.resourceGroup = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/resourcegroup')."#text"
        $this.vmsize = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/vmsize')."#text"
        $this.drVmName = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/vmname')."#text"
        $this.drResourceGroup = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/resourcegroup')."#text"
        $this.drStorageAccount = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/storageaccount')."#text"
        $this.drContainer = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/container')."#text"
        $this.drLocation = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/location')."#text"
        $this.drDiskAccounttype = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/diskaccounttype')."#text"
        $this.drVnet = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/vnet')."#text"
        $this.drSubnet = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/subnet')."#text"
        $this.drIPaddress = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/ipaddress')."#text"
        $this.drVmSize = $this.xmlFile.SelectNodes('.//config/vminfo/subscription/vm[@name="' + $vmname + '"]/dr/vmsize')."#text"
        
        return 0

    };
    
    return $obj
}
