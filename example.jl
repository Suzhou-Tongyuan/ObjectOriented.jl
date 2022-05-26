using PyStyle

@oodef struct IVehicle
    function get_speed end
    function info end
end

@oodef mutable struct Vehicle <: Vehicle begin
    m_speed :: Int
    function new(speed)
        @construct begin
            m_speed = speed
        end
    end
end

@oodef mutable struct Bus <: Vehicle
    
    function new(speed::Int)
        @construct begin
            @base(Vehicle) = Vehicle(speed)
        end
    end

    function info(self)
        ""
    end

    function get_speed(self)
        self.m_speed
    end
end

@oodef struct IHouse begin
    function get_bednumber end
    function can_cook end
end

@oodef mutable struct House <: IHouse
    m_bednumber :: Int
    
    function new(bednumber::Int)
        @construct begin
            m_bednumber = bednumber
        end
    end
    
    @override function get_bednumber(self)
        m_bednumber
    end

    @override function can_cook(self)
        true
    end
end


@oodef mutable struct HouseBus <: {Bus, House}
    m_kind :: String
    
    function HouseBus(bednumber::Int, speed::Float64, kind :: String)
        @construct begin
            @base(Bus)=Bus(speed)
            @base(House)=House(bednumber)
            m_kind=kind
        end
    end
    
    function get_kind(self)
        m_kind
    end

    function set_kind(self, v)
        self.m_kind = v
    end

    function info(self)
        "kind = $(self.m_kind), speed = $(self.get_speed()), bednumber=$(self.get_bednumber())"
    end
    
end


housebuses = [HouseBus(1, 80.0, "oil") for _ in 1:10]
housebuses[2].set_kind("electricity")

# function f(buses::Vector)
#     for bus in buses
#         if bus isa HouseBus
#             bus.cook()
#         end
#         println(bus.info())
#     end
# end

# f(housebuses)
