#!/usr/bin/env python

# Generate images of an icosahedron.

import numpy as np
import matplotlib.pyplot as pl

n = 12  # Total vertices
m = 5   # Number of neighbours per vertex

rng = np.random.default_rng(seed=0)
points = rng.random(size=(n,3))

# Helper method: find 5 closest points for each point
# Input array: 12 x 3
# Output array: 12 x 5
def closest (points):
    out = []
    for i in range(n):
        #sorted_points = sorted(points, key=lambda p: np.linalg.norm(p-points[i]))
        sorted_points = sorted(range(n), key = lambda j: np.linalg.norm(points[j]-points[i]))
        out.append(sorted_points[1:m+1])
    return np.array(out)

# Helper method: redistribute points.
def respread (points):
    out = []
    for i, p in enumerate(points):
        f = [0,0,0]
        for j, other in enumerate(points):
            if j == i: continue
            v = p-other
            f += v/np.linalg.norm(v)**2
        out.append(p + f*0.1)
    return np.array(out)

# Helper method: normalize points to be centered at (0,0,0) and with
# magnitude of 1.
def normalize (points):
    points -= np.mean(points,axis=0,keepdims=True)
    norm = np.linalg.norm(points,axis=1,keepdims=True)
    points /= norm
    return points

points = normalize(points)

# Distribute and normalize.
for i in range(1000):
    # Distribute points
    points = respread(points)
    points = normalize(points)

# Rotate the points by the specified angle.
def rotate (points, angle):
    from math import sqrt, sin, cos
    # Align the rotation axis.
    t = np.array([
        [1/sqrt(2), -1/sqrt(2), 0],
        [1/sqrt(2), 1/sqrt(2), 0],
        [0, 0, 1]
    ])
    points = [t@p for p in points]

    s = sin(angle)
    c = cos(angle)
    r = np.array([
        [c, 0, -s],
        [0, 1, 0],
        [s, 0, c]
    ])
    points = [r@p for p in points]

    tinv = np.linalg.inv(t)
    points = [tinv@p for p in points]

    return np.array(points)

indices = closest (points)

# Get the coordinates of all the triangles.
triangles = set()

for i in range(n):
    for j in indices[i]:
        for k in set(indices[i]) & set(indices[j]):  # 2 elements
            triangle = tuple(sorted((i,j,k)))
            triangles.add(triangle)

# Draw into an image
pixels = 256
final_size = 32

true = np.ones((pixels,pixels),dtype='bool')
p = np.zeros((2,pixels,pixels),dtype=float)
p[0,:,:] = np.linspace(-1,1,pixels).reshape(-1,1)
p[1,:,:] = np.linspace(-1,1,pixels).reshape(1,-1)

# Helper: 2D cross-product.
def cross (p1, p2):
    return p1[0]*p2[1] - p1[1]*p2[0]

def draw_triangle (triangle):
    p1 = triangle[0]
    p2 = triangle[1]
    p3 = triangle[2]
    # Get conditions for points being inside the triangle.
    inside1 = np.sign(cross(p2-p1,p-p1[:,None,None])) == np.sign(cross(p2-p1,p3-p1))
    inside2 = np.sign(cross(p3-p2,p-p2[:,None,None])) == np.sign(cross(p3-p2,p1-p2))
    inside3 = np.sign(cross(p1-p3,p-p3[:,None,None])) == np.sign(cross(p1-p3,p2-p3))
    mask = inside1 & inside2 & inside3
    return mask

qmark = pl.imread("questionmark.png")

def render_frame (points, progress=0.0):
    from math import sqrt, pi
    # a161fe
    colour = np.array([0xa1/255,0x61/255,0xfe/255,1.0])
    ray_colour = np.array([1.0,1.0,0.5,0.5])
    image = np.zeros((pixels,pixels,4),dtype=float)
    # For fading to transparency, use ray colour.
    image[:,:,0] = ray_colour[0]
    image[:,:,1] = ray_colour[1]
    image[:,:,2] = ray_colour[2]
    # Rays
    nrays = 11
    x = p[0,:,:]
    y = p[1,:,:]
    r2 = x**2 + y**2
    angle = np.arctan2(y,x)
    rays = np.cos(2*pi*progress)*np.cos(angle*nrays) + np.cos(4*pi*(progress+0.1))*np.cos((angle+0.1)*(nrays+3)) + np.cos(6*pi*progress)*np.cos((angle+0.2)*(nrays+5)) + np.cos(8*pi*progress)*np.cos((angle+0.3)*(nrays+7))
    rays /= 4
    rays = rays - r2 + 1/r2
    rays[rays<0] = 0
    rays[rays>1] = 1
    image[:,:,:3] = ray_colour[None,None,:3]
    image[:,:,3] = rays[:,:]

    for triangle in triangles:
        # Convert from indices to points in 3D
        triangle = [points[i] for i in triangle]
        # Get normal direction to the triangle.
        norm = np.mean(triangle,axis=0)
        norm /= np.linalg.norm(norm)
        # Ignore triangles in the back.
        if norm[2] < 0: continue
        # Shading is based on angle of surface normal to some
        # reference direction.
        ref = np.array([-1,1,1],dtype=float)
        #ref = np.array([0,0,1],dtype=float)
        ref /= np.linalg.norm(ref)
        shade = np.dot(ref,norm)
        # Specular reflection
        spec = shade**3 if shade > 0 else 0
        #shade = max(shade,0.5)
        shade = (shade+1)/2 * (1-0.3) + 0.3
        # Reduce to 2D triangle coordinates.
        p1 = triangle[0][:2]
        p2 = triangle[1][:2]
        p3 = triangle[2][:2]
        # Consistent order of points.
        if cross(p3-p1,p2-p1) < 0:
            p2, p3 = p3, p2
        # Get triangle mask (full size).
        mask = draw_triangle((p1,p2,p3))
        # Apply edge shading.
        image[...,0][mask] = 0
        image[...,1][mask] = 0
        image[...,2][mask] = 0
        image[...,3][mask] = colour[3]
        # Get triangle mask (inner).
        middle = (p1+p2+p3)/3
        p1 = middle + (p1-middle)*0.99
        p2 = middle + (p2-middle)*0.99
        p3 = middle + (p3-middle)*0.99
        mask = draw_triangle((p1,p2,p3))
        # Apply base shading.
        image[...,0][mask] = shade*colour[0]
        image[...,1][mask] = shade*colour[1]
        image[...,2][mask] = shade*colour[2]
        image[...,3][mask] = colour[3]
        # Add question mark image.
        # Map to triangle coordinates.
        # Using p1 as origin.
        t = p - p1[:,None,None]
        # Transformation matrix
        start = np.array([p2-p1, p3-p1]).T
        end = np.array([[1,0],[0.5,sqrt(3)/2]]) * qmark.shape[0]
        transform = end @ np.linalg.inv(start)
        t = t.reshape(2,-1)
        t = transform @ t
        t = t.reshape(2,pixels,pixels)
        t = np.round(t).astype(int)
        t[t<0] = 0
        t[t>=qmark.shape[0]] = 0
        q = qmark[t[0],t[1]]
        q[~mask] = 0
        q[:,:,0] *= shade
        q[:,:,1] *= shade
        q[:,:,2] *= shade
        image[q>0] = q[q>0]
        # Apply specular reflection.
        image[...,:][mask] = spec + (1-spec)*image[...,:][mask]

    # Flip y axis for image.
    image = image[:,::-1].copy()
    image = image.reshape(final_size,pixels//final_size,final_size,pixels//final_size,4)
    image = np.mean(image, axis=(1,3))
    return image


nframes = 120
image = np.zeros((final_size,final_size*nframes,4),float)
from math import pi
dr = 2*pi/nframes
for f in range(nframes):
    image[:,f*final_size:(f+1)*final_size,:] = render_frame(rotate(points,dr*f),f/nframes)
    #image = render_frame(rotate(points,dr*f))
    #pl.imshow(image)
    #pl.show()
    #break

pl.imsave("d20.png",image)

