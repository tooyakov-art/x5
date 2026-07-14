[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$TargetCourseId = '892fc2d1-f521-48a2-800f-a90eb9e1a852'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$parsedTargetId = [Guid]::Empty
if (-not [Guid]::TryParse($TargetCourseId, [ref]$parsedTargetId)) {
    throw "TargetCourseId must be a UUID."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$backupDirectory = Join-Path $repoRoot 'diagnostics/course-repair'
New-Item -ItemType Directory -Force $backupDirectory | Out-Null
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$newCourseTitle = -join @(
    [char]0x041D, [char]0x043E, [char]0x0432, [char]0x044B, [char]0x0439,
    [char]0x0020, [char]0x043A, [char]0x0443, [char]0x0440, [char]0x0441
)
$moduleOneTitle = -join @(
    [char]0x041E, [char]0x0441, [char]0x043D, [char]0x043E, [char]0x0432,
    [char]0x044B, [char]0x0020, [char]0x0442, [char]0x0430, [char]0x0440,
    [char]0x0433, [char]0x0435, [char]0x0442, [char]0x0430
)
# PostgreSQL Unicode-escape literals keep the command passed through npx.cmd ASCII-only.
$newCourseTitleSql = "U&'\041D\043E\0432\044B\0439\0020\043A\0443\0440\0441'"
$moduleOneTitleSql = "U&'\041E\0441\043D\043E\0432\044B\0020\0442\0430\0440\0433\0435\0442\0430'"

function Invoke-LinkedSupabaseQuery {
    param([Parameter(Mandatory = $true)][string]$Sql)

    $npx = (Get-Command npx.cmd -ErrorAction Stop).Source
    # Windows PowerShell invokes npx through a .cmd shim. Newlines in a single
    # argument are split by that shim, so normalize SQL before passing it on.
    $singleLineSql = ($Sql -replace '[\r\n]+', ' ').Trim()
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = & $npx --yes supabase@latest db query --linked --output json $singleLineSql 2>$null | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($exitCode -ne 0) {
        throw "Supabase query failed with exit code $exitCode."
    }

    $parsed = $raw | ConvertFrom-Json
    return @($parsed.rows)
}

function Write-Snapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object[]]$Rows
    )

    $path = Join-Path $backupDirectory "$timestamp-$Name.json"
    $payload = [ordered]@{
        captured_at = (Get-Date).ToUniversalTime().ToString('o')
        project_ref = 'afwznqjpshybmqhlewmy'
        target_course_id = $TargetCourseId
        rows = $Rows
    }
    $payload | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding UTF8
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    [PSCustomObject]@{ Path = $path; SHA256 = $hash }
}

function Get-CategoryByTitle {
    param(
        [Parameter(Mandatory = $true)]$Course,
        [Parameter(Mandatory = $true)][string]$Title
    )

    @($Course.categories | Where-Object { $_.title -eq $Title } | Select-Object -First 1)
}

function Get-VideoUrls {
    param([Parameter(Mandatory = $true)]$Course)

    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($category in @($Course.categories)) {
        foreach ($day in @($category.days)) {
            foreach ($lesson in @($day.lessons)) {
                if ($lesson.videoUrl -and -not [string]::IsNullOrWhiteSpace([string]$lesson.videoUrl)) {
                    $urls.Add([string]$lesson.videoUrl)
                }
            }
        }
    }
    @($urls)
}

$selectSql = @"
select
  id::text,
  title,
  author_name,
  is_public,
  price,
  created_at,
  updated_at,
  categories
from public.courses
where id = '$TargetCourseId'::uuid
   or title = $newCourseTitleSql
order by created_at, id;
"@

$beforeRows = @(Invoke-LinkedSupabaseQuery -Sql $selectSql)
$target = @($beforeRows | Where-Object { $_.id -eq $TargetCourseId }) | Select-Object -First 1
if (-not $target) {
    throw "Target course $TargetCourseId was not found."
}

$duplicates = @($beforeRows | Where-Object {
    $_.title -eq $newCourseTitle -and @(Get-CategoryByTitle -Course $_ -Title $moduleOneTitle).Count -gt 0
})
if ($duplicates.Count -eq 0) {
    throw "No recovery source containing the first module was found."
}

$beforeSnapshot = Write-Snapshot -Name 'before' -Rows $beforeRows

$source = $duplicates | Select-Object -First 1
$sourceId = [string]$source.id
$parsedSourceId = [Guid]::Empty
if (-not [Guid]::TryParse($sourceId, [ref]$parsedSourceId)) {
    throw "Recovery source ID is not a UUID."
}

$duplicateIds = @($duplicates | ForEach-Object {
    $candidate = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$_.id, [ref]$candidate)) {
        throw "Duplicate course ID is not a UUID."
    }
    "'$([string]$_.id)'::uuid"
})

$hadRecoveredModule = @(Get-CategoryByTitle -Course $target -Title $moduleOneTitle).Count -gt 0
$beforeVideoUrls = @(Get-VideoUrls -Course $target)
$quotedDuplicateIds = $duplicateIds -join ', '

$plan = [ordered]@{
    mode = if ($Apply) { 'apply' } else { 'dry-run' }
    target_course_id = $TargetCourseId
    source_course_id = $sourceId
    duplicate_course_ids = @($duplicates.id)
    target_author = $target.author_name
    target_video_count = $beforeVideoUrls.Count
    module_already_present = $hadRecoveredModule
    before_snapshot = $beforeSnapshot.Path
    before_sha256 = $beforeSnapshot.SHA256
}

if (-not $Apply) {
    $planPath = Join-Path $backupDirectory "$timestamp-dry-run.json"
    $plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $planPath -Encoding UTF8
    Write-Output ($plan | ConvertTo-Json -Depth 20)
    Write-Output "Dry run complete. Re-run with -Apply after reviewing $planPath"
    exit 0
}

$mutationSql = @"
begin;

update public.courses as target
set categories = case
    when exists (
      select 1
      from jsonb_array_elements(coalesce(target.categories, '[]'::jsonb)) as category
      where category ->> 'title' = $moduleOneTitleSql
    ) then target.categories
    else (
      select jsonb_build_array(source_category.category) || coalesce(target.categories, '[]'::jsonb)
      from public.courses as source_course
      cross join lateral jsonb_array_elements(coalesce(source_course.categories, '[]'::jsonb)) as source_category(category)
      where source_course.id = '$sourceId'::uuid
        and source_category.category ->> 'title' = $moduleOneTitleSql
      limit 1
    )
  end,
  updated_at = now()
where target.id = '$TargetCourseId'::uuid;

update public.courses
set is_public = false,
    updated_at = now()
where id in ($quotedDuplicateIds);

commit;

select id::text, title, author_name, is_public, price, created_at, updated_at, categories
from public.courses
where id = '$TargetCourseId'::uuid
   or id in ($quotedDuplicateIds)
order by created_at, id;
"@

$afterRows = @(Invoke-LinkedSupabaseQuery -Sql $mutationSql)
$afterSnapshot = Write-Snapshot -Name 'after' -Rows $afterRows
$afterTarget = @($afterRows | Where-Object { $_.id -eq $TargetCourseId }) | Select-Object -First 1
if (-not $afterTarget) {
    throw "Post-repair target verification failed: target row missing."
}
if (@(Get-CategoryByTitle -Course $afterTarget -Title $moduleOneTitle).Count -ne 1) {
    throw "Post-repair target verification failed: recovered module count is not one."
}
if ([string]$afterTarget.author_name -ne [string]$target.author_name) {
    throw "Post-repair target verification failed: author changed."
}

$afterVideoUrls = @(Get-VideoUrls -Course $afterTarget)
foreach ($url in $beforeVideoUrls) {
    if ($afterVideoUrls -notcontains $url) {
        throw "Post-repair target verification failed: an existing video URL was lost."
    }
}

$stillPublic = @($afterRows | Where-Object { $_.id -ne $TargetCourseId -and $_.is_public -eq $true })
if ($stillPublic.Count -gt 0) {
    throw "Post-repair verification failed: at least one duplicate is still public."
}

$result = [ordered]@{
    status = 'repaired'
    target_course_id = $TargetCourseId
    categories = @($afterTarget.categories).Count
    preserved_video_urls = $beforeVideoUrls.Count
    hidden_duplicates = $duplicates.Count
    before_snapshot = $beforeSnapshot.Path
    before_sha256 = $beforeSnapshot.SHA256
    after_snapshot = $afterSnapshot.Path
    after_sha256 = $afterSnapshot.SHA256
}
Write-Output ($result | ConvertTo-Json -Depth 20)
