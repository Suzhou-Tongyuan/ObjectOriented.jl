using TyOOP

@oodef struct IVehicle
    function get_speed end
    function info end
end

@oodef mutable struct Vehicle <: IVehicle
    m_speed :: Float64
    function new(speed)
        @mk begin
            m_speed = speed
        end
    end
end

@oodef mutable struct Bus <: Vehicle
    function new(speed::Float64)
        @mk begin
            Vehicle(speed)
        end
    end

    # override
    function info(self)
        ""
    end

    # override
    function get_speed(self)
        self.m_speed
    end
end

@oodef struct IHouse
    function get_rooms end
    function set_rooms end
    function can_cook end
end

@oodef mutable struct House <: IHouse
    m_rooms :: Int
    
    function new(rooms::Int)
        @mk begin
            # IHouse()
            m_rooms = rooms
        end
    end
    # class methods

    # virtual methods
    # override
    function get_rooms(self)
        self.m_rooms
    end

    # override
    function set_rooms(self, value)
        self.m_rooms = value
    end

    # override
    function can_cook(self)
        true
    end
end


@oodef mutable struct HouseBus <: {Bus, House}
    m_power :: String
    
    function new(speed::Float64, rooms::Int, power :: String = "oil")
        @mk begin
            Bus(speed), House(rooms)
            m_power = power
        end
    end
    
    function get_power(self)
        self.m_power
    end

    function set_power(self, v)
        self.m_power = v
    end

    # override
    function info(self)
        "power = $(self.m_power), " *
        "speed = $(self.get_speed()), " *
        "rooms=$(self.get_rooms())"
    end
end

@oodef mutable struct RailBus <: {Bus}
    m_power :: String
    
    function new(speed::Float64)
        @mk begin
            Bus(speed)
            m_power="electricity"
        end
    end
    
    function get_power(self)
        self.m_power
    end

    # override
    function info(self)
        "power = $(self.m_power), " *
        "speed = $(self.get_speed())"
    end
end

housebuses = @like(IVehicle)[
    [HouseBus(rand(Float64), 2) for i in 1:5000]...,
    [RailBus(rand(Float64)) for i in 1:5000]...
]

any_buses = Any[
    [HouseBus(rand(Float64), 2) for i in 1:5000]...,
    [RailBus(rand(Float64)) for i in 1:5000]...
]

union_buses = Union{HouseBus, RailBus}[
    [HouseBus(rand(Float64), 2) for i in 1:5000]...,
    [RailBus(rand(Float64)) for i in 1:5000]...
]

monotype_buses = HouseBus[
    [HouseBus(rand(Float64), 2) for i in 1:10000]...,
]


function f(buses::Vector)
    for bus in buses
        info = bus.info()
        if bus isa HouseBus
            cook = bus.can_cook()
            @info typeof(bus) info cook
        else
            @info typeof(bus) info
        end
    end
end

function sum_speeds(buses::Vector)
    sum(buses; init=0.0) do bus
        bus.get_speed()
    end
end

function sum_speeds_forloop(buses::Vector)
    s = 0.0
    @inbounds for bus in buses
        s += bus.get_speed() :: Float64
    end
    s
end

function g(o::@like(IVehicle))
    o.get_speed()
end

function g(o::HouseBus)
    x = get_base(o, Bus)
    @typed_access x.get_speed()
end

hb = HouseBus(80.0, 2)
rb = RailBus(80.0)

using InteractiveUtils
@info :housebus code_typed(g, (HouseBus, ))
@info :housebus @code_typed g(hb)
@info :housebus @code_llvm g(hb)


# @info :railbus @code_llvm g(rb)


using BenchmarkTools
# @btime sum_speeds(housebuses)
# @btime sum_speeds(any_buses)
# @btime sum_speeds(union_buses)
# @btime sum_speeds(monotype_buses)

@btime sum_speeds_forloop(housebuses)
@btime sum_speeds_forloop(any_buses)
@btime sum_speeds_forloop(union_buses)
@btime sum_speeds_forloop(monotype_buses)

