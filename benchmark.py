import abc

class IVehicle(abc.ABC):

    @abc.abstractmethod
    def get_speed(self):
        raise NotImplementedError
                        
    @abc.abstractmethod
    def info(self):
        raise NotImplementedError

class Vehicle(IVehicle):
    m_speed: float
    def __init__(self, speed):
        self.m_speed = speed

class Bus(Vehicle):
    def __init__(self, speed):
        Vehicle.__init__(self, speed)

    def info(self):
        return ""
    
    def get_speed(self):
        return self.m_speed
    
class IHouse(abc.ABC):    
    @abc.abstractmethod
    def get_rooms(self):
        raise NotImplementedError

    @abc.abstractmethod
    def set_rooms(self, value):
        raise NotImplementedError

    @abc.abstractmethod
    def can_cook(self):
        raise NotImplementedError
    
class House(IHouse):
    m_rooms: int
    def __init__(self, rooms):
        self.m_rooms = rooms
    
    def get_rooms(self):
        return self.m_rooms
    
    def set_rooms(self, value):
        self.m_rooms = value
    
    def can_cook(self):
        return True

class HouseBus(House, Bus):
    m_power: str

    def __init__(self, rooms, speed, power = "oil"):
        House.__init__(self, rooms)
        Bus.__init__(self, speed)
        self.m_power = power

    def get_power(self):
        return self.m_power
    
    def set_power(self, value):
        self.m_power = value
    
    def info(self):
        return (
            f"power = {self.m_power}, "
            f"speed = {self.get_speed()}, "
            f"rooms = {self.get_rooms()}"
        )

class RailBus(Bus):
    m_power: str

    def __init__(self, speed):
        Bus.__init__(self, speed)
        self.m_power = "steam"
    
    def get_power(self):
        return self.m_power
    
    def info(self):
        return (
            f"power = {self.m_power}, "
            f"speed = {self.get_speed()}"
        )

import random
housebuses = [
    *[HouseBus(random.random(), 2) for i in range(5000)],
    *[RailBus(random.random()) for i in range(5000)],
]

def sum_speeds(buses: list[IVehicle]):
    return sum(map(lambda x: x.get_speed(), buses), 0.0)

def sum_speeds_forloop(buses: list[IVehicle]):
    s = 0.0
    for bus in buses:
        s += bus.get_speed()
    return s

import timeit
def test_in_nanoseconds(code, number=500):
    timer = timeit.Timer(code, globals=globals())
    print(timer.timeit(number) / number * 10**6, 'us')

test_in_nanoseconds("sum_speeds(housebuses)")
test_in_nanoseconds("sum_speeds_forloop(housebuses)")
