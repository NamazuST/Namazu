import numpy as np
###################################################################################################################################
#Implementation of the Spectral Representation Method, Shinozuka & Deodatis (1991)
###################################################################################################################################
def SpectralRepresentationMethod(S, w, t):
    Nt = len(t)
    Nw = len(w)
    dw = w[1] - w[0]
    
    x_shnzk = np.zeros(Nt)
    
    for w_n in range(Nw):
        if w[w_n] == 0:
            A = 0
        else:
            A = np.sqrt(2 * S(w[w_n]) * dw)
        
        phi = np.random.rand() * (2 * np.pi)
        x_shnzk += np.sqrt(2) * A * np.cos(w[w_n] * t + phi)
    
    return x_shnzk