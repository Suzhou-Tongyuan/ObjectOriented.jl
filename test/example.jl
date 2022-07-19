module Example
using Test
using ObjectOriented

DoPrint = Ref(false)

@oodef struct IVehicle
    function get_speed end
    function info end
end

@oodef mutable struct Vehicle <: IVehicle
    m_speed::Float64
    function new(speed)
        @mk begin
            m_speed = speed
        end
    end
end

@oodef mutable struct Bus <: Vehicle
    function new(speed::Float64)
        @mk Vehicle(speed)
    end

    # override
    function info(self)
        ""
    end

    # override
    function get_speed(self)
        return self.m_speed
    end
end

@oodef struct IHouse
    @property(rooms) do
        get
        set
    end
    function can_cook end
end

@oodef mutable struct House <: IHouse
    m_rooms::Int

    function new(rooms::Int)
        @mk begin
            # @base(IHouse) = IHouse()
            m_rooms = rooms
        end
    end

    @property(rooms) do
        get = function (self)
            self.m_rooms
        end
        set = function (self, value)
            self.m_rooms = value
        end    
    end

    # override
    function can_cook(self)
        true
    end
end

@oodef mutable struct HouseBus <: {Bus, House}
    m_power::String

    function new(speed::Float64, rooms::Int, power::String = "oil")
        self = new()
        self.m_power = power
        set_base!(self, Bus(speed))
        set_base!(self, House(rooms))
        return self
        # @mk begin
        #     @base(Bus) = Bus(speed)
        #     @base(House) = House(rooms)
        #     m_power = power
        # end
    end

    @property(power) do
        get = self -> self.m_power
        set = (self, value) -> self.m_power = value
    end

    # override
    function info(self)
        "power = $(self.m_power), " *
        "speed = $(self.get_speed()), " *
        "rooms=$(self.rooms)"
    end
end



@oodef mutable struct RailBus <: {Bus}
    m_power::String

    function new(speed::Float64)
        @mk begin
            Bus(speed)
            m_power = "electricity"
        end
    end

    @property(power) do
        get = self -> self.m_power
    end

    # override
    function info(self)
        "power = $(self.m_power), " *
        "speed = $(self.get_speed())"
    end
end

housebuses = [
    [HouseBus(60.0, 2) for i = 1:10000];
    [RailBus(80.0) for i = 1:10000]
]

res = []
function f(buses::Vector)
    for bus in buses
        info = bus.info()
        if bus isa HouseBus
            cook = bus.can_cook()
            if DoPrint[]
                @info typeof(bus) info cook
            else
                push!(res, (typeof(bus), info, cook))
            end
        else
            if DoPrint[]
                @info typeof(bus) info
            else
                push!(res, (typeof(bus), info))
            end
        end
    end
end


function get_speed(o::@like(IVehicle))
    o.get_speed()
end

using InteractiveUtils

function runtest()
    @testset "example" begin
        f(housebuses)
        hb = HouseBus(60.0, 2)
        rb = RailBus(80.0)
        get_speed(hb)
        get_speed(rb)
    end
end

end
    
