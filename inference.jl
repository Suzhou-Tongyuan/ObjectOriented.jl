using TyOOP

@oodef struct IVehicle
    function get_speed end
    function info end
end

@oodef mutable struct Vehicle <: IVehicle
    m_speed :: Float64
    function new(speed)
        @construct begin
            m_speed = speed
        end
    end
end

@oodef mutable struct Bus <: Vehicle
    function new(speed::Float64)
        @construct begin
            @base(Vehicle) = Vehicle(speed)
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

f(x) = x.get_speed()

code_warntype(f, (Bus, ))