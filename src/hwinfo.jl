struct HwInfo
    cpus::Vector{CPUinfo}
    machine::String
    word::Int
    simdbytes::Int
    corecount::Tuple{Int, Int, Int}
end
function HwInfo()
    cc = (cpucores(), cputhreads(), cputhreads_per_core())
    return HwInfo(cpu_info(), CPU_NAME, WORD_SIZE, simdbytes(), cc)
end

# Function to convert HwInfo to a dictionary for JSON serialization
function hwinfo_to_dict(hwinfo::HwInfo)
    return Dict(
        "cpus" => hwinfo.cpus,
        "machine" => hwinfo.machine,
        "word" => hwinfo.word,
        "simdbytes" => hwinfo.simdbytes,
        "corecount" => hwinfo.corecount
    )
end

# Function to write HwInfo and UUID to a JSON file
function write_hwinfo_to_json(hwinfo::HwInfo, u::UUID; path::String = "")
    filename = joinpath(path, "$(u).json")
    hwinfo_dict = hwinfo_to_dict(hwinfo)
    hwinfo_dict["uuid"] = string(u)

    # Write to the JSON file
    open(filename, "w") do io
        JSON.print(io, hwinfo_dict)
    end
end

# Helper function to convert a dictionary back to CPUinfo
function dict_to_cpuinfo(dict::Dict)
    return CPUinfo(
        dict["model"], dict["speed"], dict["cpu_times!user"], dict["cpu_times!nice"],
        dict["cpu_times!sys"], dict["cpu_times!idle"], dict["cpu_times!irq"])
end

# Function to load HwInfo from a JSON file
function load_hwinfo_from_json(filepath::String)
    if !isfile(filepath)
        error("File $filepath does not exist.")
    end

    data = open(filepath, "r") do io
        JSON.parse(io)
    end

    cpus = [dict_to_cpuinfo(cpu) for cpu in data["cpus"]]

    HwInfo(
        cpus,
        data["machine"],
        data["word"],
        data["simdbytes"],
        (data["corecount"][1], data["corecount"][2], data["corecount"][3])
    )
end

@testitem "Hardware identity" tags=[:unit, :hardware] begin
    import PerfChecker

    info = PerfChecker.HwInfo()
    as_dict = PerfChecker.hwinfo_to_dict(info)
    @test as_dict["machine"] == info.machine
    @test as_dict["corecount"] == info.corecount
    mktempdir() do dir
        id = PerfChecker.uuid4()
        path = joinpath(dir, "$(id).json")
        PerfChecker.write_hwinfo_to_json(info, id; path = dir)
        restored = PerfChecker.load_hwinfo_from_json(path)
        @test restored.machine == info.machine
        @test restored.word == info.word
        @test restored.corecount == info.corecount
        rm(path; force = true)
    end
end
