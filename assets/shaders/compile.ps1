$Gfx_Files=Get-ChildItem -Path .\*.gfx.slang
$Comp_Files=Get-ChildItem -Path .\*.comp.slang

foreach ($File in $Gfx_Files) {
    $Frag_Name = $File -replace '.slang', '.frag'
    $Vert_Name = $File -replace '.slang', '.vert'

    slangc.exe $File -profile glsl_450 -entry vertex_main -target spirv -o $Vert_Name
    slangc.exe $File -profile glsl_450 -entry pixel_main -target spirv -o $Frag_Name
}

foreach ($File in $Comp_Files) {

}