module Inference
using ObjectOriented
using InteractiveUtils
using Test

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

f(x) = @typed_access x.speed

@testset "inference property with @typed_access" begin
    bus = Bus(1.0)
    (@code_typed f(bus)).second === Float64
end
end