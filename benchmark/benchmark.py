class Base1:
    def __init__(self, a):
        self.a = a

    def identity_a(self):
        return self

class Base2(Base1):
    def __init__(self, a, b):
        super().__init__(a)
        self.b = b
        
    def identity_b(self):
        return self

class Base3(Base2):
    def __init__(self, a, b, c):
        super().__init__(a, b)
        self.c = c
        
    def identity_c(self):
        return self

class Base4(Base3):
    def __init__(self, a, b, c, d):
        super().__init__(a, b, c)
        self.d = d
        
    def identity_d(self):
        return self

class Base5(Base4):
    def __init__(self, a, b, c, d, e):
        super().__init__(a, b, c, d)
        self.e = e
        
    def identity_e(self):
        return self
    
o = Base5(1, 2, 3, 4, 5)

# %timeit o.a
# %timeit o.b
# %timeit o.c
# %timeit o.d
# %timeit o.e

# %timeit o.identity_a()
# %timeit o.identity_b()
# %timeit o.identity_c()
# %timeit o.identity_d()
# %timeit o.identity_e()

# 25.6 ns ± 0.114 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 27.1 ns ± 0.176 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 26.2 ns ± 0.0642 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 26.6 ns ± 0.142 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 31.2 ns ± 0.137 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 62.6 ns ± 0.578 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 59.5 ns ± 0.37 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 63.2 ns ± 1.01 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 63.7 ns ± 0.2 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)
# 62.9 ns ± 0.568 ns per loop (mean ± std. dev. of 7 runs, 10,000,000 loops each)

bases = [Base5(1, 2, 3, 4, 5) for i in range(10000)]
def sum_all(bases):
    s = 0
    for each in bases:
        s += each.a
    return s
# %timeit sum_all(bases)
