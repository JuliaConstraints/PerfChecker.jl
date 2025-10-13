
# PerfChecker.jl {#PerfChecker.jl}

Documentation for `PerfChecker.jl`.
<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.arrange_breaking-Tuple{VersionNumber, Vector{VersionNumber}, Bool}' href='#PerfChecker.arrange_breaking-Tuple{VersionNumber, Vector{VersionNumber}, Bool}'><span class="jlbinding">PerfChecker.arrange_breaking</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



Outputs the last breaking or next breaking version.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.arrange_major-Tuple{VersionNumber, Vector{VersionNumber}, Bool}' href='#PerfChecker.arrange_major-Tuple{VersionNumber, Vector{VersionNumber}, Bool}'><span class="jlbinding">PerfChecker.arrange_major</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



Outputs the earlier or next major version.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.arrange_patches-Tuple{VersionNumber, Vector{VersionNumber}, Bool}' href='#PerfChecker.arrange_patches-Tuple{VersionNumber, Vector{VersionNumber}, Bool}'><span class="jlbinding">PerfChecker.arrange_patches</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



Outputs the last patch or first patch of a version.


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.checkres_to_boxplots' href='#PerfChecker.checkres_to_boxplots'><span class="jlbinding">PerfChecker.checkres_to_boxplots</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



General Usage: Takes the output of a check macro, and creates a boxplot. 


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.checkres_to_pie' href='#PerfChecker.checkres_to_pie'><span class="jlbinding">PerfChecker.checkres_to_pie</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



General Usage: Takes the output of a check macro as input, and creates a pie plot. Uses `table_to_pie` internally. 


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.checkres_to_scatterlines' href='#PerfChecker.checkres_to_scatterlines'><span class="jlbinding">PerfChecker.checkres_to_scatterlines</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



General Usage: Takes the output of a check macro as input, and creates a scatterlines plot. 


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.find_by_tags-Tuple{Vector{Symbol}, PerfChecker.CheckerResult}' href='#PerfChecker.find_by_tags-Tuple{Vector{Symbol}, PerfChecker.CheckerResult}'><span class="jlbinding">PerfChecker.find_by_tags</span></a> <Badge type="info" class="jlObjectType jlMethod" text="Method" /></summary>



Usage: (Assuming you ran the &#39;Basic Example&#39;)

```julia
julia> find_by_tags([:example, :nice, :great], res)
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.get_pkg_versions' href='#PerfChecker.get_pkg_versions'><span class="jlbinding">PerfChecker.get_pkg_versions</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



Finds all versions of a package in all the installed registries and returns it as a vector.

Example:

```julia
julia> get_pkg_versions("ConstraintLearning")
7-element Vector{VersionNumber}:
 v"0.1.4"
 v"0.1.5"
 v"0.1.0"
 v"0.1.6"
 v"0.1.1"
 v"0.1.3"
 v"0.1.2"
```



<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.table_to_pie' href='#PerfChecker.table_to_pie'><span class="jlbinding">PerfChecker.table_to_pie</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



General Usage: Takes a table generated via the check macro as input, and creates a pie plot. 


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.to_table' href='#PerfChecker.to_table'><span class="jlbinding">PerfChecker.to_table</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



General Usage: Returns a table from the output of the results of respective backends 


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

<details class='jldocstring custom-block' open>
<summary><a id='PerfChecker.@check-NTuple{4, Any}' href='#PerfChecker.@check-NTuple{4, Any}'><span class="jlbinding">PerfChecker.@check</span></a> <Badge type="info" class="jlObjectType jlMacro" text="Macro" /></summary>



General usage:

```julia
@check :name_of_backend config_dictionary begin
    # the prelimnary code
end begin
    # the actual code you want to do perf testing for
end
```


Outputs a `CheckerResult` which can be used with other functions.  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/JuliaConstraints/PerfChecker.jl" target="_blank" rel="noreferrer">source</a></Badge>

</details>

