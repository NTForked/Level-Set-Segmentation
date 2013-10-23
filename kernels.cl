__constant sampler_t sampler = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_NEAREST;
__constant sampler_t hpSampler = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP | CLK_FILTER_NEAREST;

#ifdef NO_3D_WRITE
#define FLOAT_TYPE __global float *
#define CHAR_TYPE __global char *
#define READ_FLOAT(buffer, pos) buffer[(pos).x+(pos).y*get_global_size(0)+(pos).z*get_global_size(0)*get_global_size(1)]
#define READ_INT(buffer,pos) buffer[(pos).x+(pos).y*get_global_size(0)+(pos).z*get_global_size(0)*get_global_size(1)]
#define WRITE_FLOAT(storage, pos, value) storage[(pos).x+(pos).y*get_global_size(0)+(pos).z*get_global_size(0)*get_global_size(1)] = value;
#define WRITE_INT(storage, pos, value) storage[(pos).x+(pos).y*get_global_size(0)+(pos).z*get_global_size(0)*get_global_size(1)] = value;
#else
#pragma OPENCL EXTENSION cl_khr_3d_image_writes : enable
#define FLOAT_TYPE image3d_t
#define CHAR_TYPE image3d_t
#define WRITE_FLOAT(storage, pos, value) write_imagef(storage, pos, value)
#define WRITE_INT(storage, pos, value) write_imagei(storage, pos, value)
#define READ_FLOAT(image,pos) read_imagef(image,sampler,pos).x
#define READ_INT(image,pos) read_imagei(image,sampler,pos).x
#endif


__kernel void updateLevelSetFunction(
        __read_only image3d_t input,
        __global int * positions,
        __private int activeVoxels,
        __read_only FLOAT_TYPE phi_read,
        __write_only FLOAT_TYPE phi_write,
        __private float threshold,
        __private float epsilon,
        __private float alpha
        ) {
    int id = get_global_id(0) >= activeVoxels ? 0 : get_global_id(0);
    const int3 position = vload3(id, positions);
    const int x = position.x;
    const int y = position.y;
    const int z = position.z;
    const int4 pos = {x,y,z,0};

    // Calculate all first order derivatives
    float3 D = {
            0.5f*(READ_FLOAT(phi_read,(int4)(x+1,y,z,0))-READ_FLOAT(phi_read,(int4)(x-1,y,z,0))),
            0.5f*(READ_FLOAT(phi_read,(int4)(x,y+1,z,0))-READ_FLOAT(phi_read,(int4)(x,y-1,z,0))),
            0.5f*(READ_FLOAT(phi_read,(int4)(x,y,z+1,0))-READ_FLOAT(phi_read,(int4)(x,y,z-1,0)))
    };
    float3 Dminus = {
            READ_FLOAT(phi_read,pos)-READ_FLOAT(phi_read,(int4)(x-1,y,z,0)),
            READ_FLOAT(phi_read,pos)-READ_FLOAT(phi_read,(int4)(x,y-1,z,0)),
            READ_FLOAT(phi_read,pos)-READ_FLOAT(phi_read,(int4)(x,y,z-1,0))
    };
    float3 Dplus = {
            READ_FLOAT(phi_read,(int4)(x+1,y,z,0))-READ_FLOAT(phi_read,pos),
            READ_FLOAT(phi_read,(int4)(x,y+1,z,0))-READ_FLOAT(phi_read,pos),
            READ_FLOAT(phi_read,(int4)(x,y,z+1,0))-READ_FLOAT(phi_read,pos)
    };

    // Calculate gradient
    float3 gradientMin = {
            sqrt(pow(min(Dplus.x, 0.0f), 2.0f) + pow(min(-Dminus.x, 0.0f), 2.0f)),
            sqrt(pow(min(Dplus.y, 0.0f), 2.0f) + pow(min(-Dminus.y, 0.0f), 2.0f)),
            sqrt(pow(min(Dplus.z, 0.0f), 2.0f) + pow(min(-Dminus.z, 0.0f), 2.0f))
    };
    float3 gradientMax = {
            sqrt(pow(max(Dplus.x, 0.0f), 2.0f) + pow(max(-Dminus.x, 0.0f), 2.0f)),
            sqrt(pow(max(Dplus.y, 0.0f), 2.0f) + pow(max(-Dminus.y, 0.0f), 2.0f)),
            sqrt(pow(max(Dplus.z, 0.0f), 2.0f) + pow(max(-Dminus.z, 0.0f), 2.0f))
    };

    // Calculate all second order derivatives
    float3 DxMinus = {
            0.0f,
            0.5f*(READ_FLOAT(phi_read,(int4)(x+1,y-1,z,0))-READ_FLOAT(phi_read,(int4)(x-1,y-1,z,0))),
            0.5f*(READ_FLOAT(phi_read,(int4)(x+1,y,z-1,0))-READ_FLOAT(phi_read,(int4)(x-1,y,z-1,0)))
    };
    float3 DxPlus = {
            0.0f,
            0.5f*(READ_FLOAT(phi_read,(int4)(x+1,y+1,z,0))-READ_FLOAT(phi_read,(int4)(x-1,y+1,z,0))),
            0.5f*(READ_FLOAT(phi_read,(int4)(x+1,y,z+1,0))-READ_FLOAT(phi_read,(int4)(x-1,y,z+1,0)))
    };
    float3 DyMinus = {
            0.5f*(READ_FLOAT(phi_read,(int4)(x-1,y+1,z,0))-READ_FLOAT(phi_read,(int4)(x-1,y-1,z,0))),
            0.0f,
            0.5f*(READ_FLOAT(phi_read,(int4)(x,y+1,z-1,0))-READ_FLOAT(phi_read,(int4)(x,y-1,z-1,0)))
    };
    float3 DyPlus = {
            0.5f*(READ_FLOAT(phi_read,(int4)(x+1,y+1,z,0))-READ_FLOAT(phi_read,(int4)(x+1,y-1,z,0))),
            0.0f,
            0.5f*(READ_FLOAT(phi_read,(int4)(x,y+1,z+1,0))-READ_FLOAT(phi_read,(int4)(x,y-1,z+1,0)))
    };
    float3 DzMinus = {
            0.5f*(READ_FLOAT(phi_read,(int4)(x-1,y,z+1,0))-READ_FLOAT(phi_read,(int4)(x-1,y,z-1,0))),
            0.5f*(READ_FLOAT(phi_read,(int4)(x,y-1,z+1,0))-READ_FLOAT(phi_read,(int4)(x,y-1,z-1,0))),
            0.0f
    };
    float3 DzPlus = {
            0.5f*(READ_FLOAT(phi_read,(int4)(x+1,y,z+1,0))-READ_FLOAT(phi_read,(int4)(x+1,y,z-1,0))),
            0.5f*(READ_FLOAT(phi_read,(int4)(x,y+1,z+1,0))-READ_FLOAT(phi_read,(int4)(x,y+1,z-1,0))),
            0.0f
    };

    // Calculate curvature
    float3 nMinus = {
            Dminus.x / sqrt(FLT_EPSILON+Dminus.x*Dminus.x+pow(0.5f*(DyMinus.x+D.y),2.0f)+pow(0.5f*(DzMinus.x+D.z),2.0f)),
            Dminus.y / sqrt(FLT_EPSILON+Dminus.y*Dminus.y+pow(0.5f*(DxMinus.y+D.x),2.0f)+pow(0.5f*(DzMinus.y+D.z),2.0f)),
            Dminus.z / sqrt(FLT_EPSILON+Dminus.z*Dminus.z+pow(0.5f*(DxMinus.z+D.x),2.0f)+pow(0.5f*(DyMinus.z+D.y),2.0f))
    };
    float3 nPlus = {
            Dplus.x / sqrt(FLT_EPSILON+Dplus.x*Dplus.x+pow(0.5f*(DyPlus.x+D.y),2.0f)+pow(0.5f*(DzPlus.x+D.z),2.0f)),
            Dplus.y / sqrt(FLT_EPSILON+Dplus.y*Dplus.y+pow(0.5f*(DxPlus.y+D.x),2.0f)+pow(0.5f*(DzPlus.y+D.z),2.0f)),
            Dplus.z / sqrt(FLT_EPSILON+Dplus.z*Dplus.z+pow(0.5f*(DxPlus.z+D.x),2.0f)+pow(0.5f*(DyPlus.z+D.y),2.0f))
    };

    float curvature = ((nPlus.x-nMinus.x)+(nPlus.y-nMinus.y)+(nPlus.z-nMinus.z))*0.5f;

    // Calculate speed term
    float speed = -alpha*(epsilon-fabs(threshold-READ_FLOAT(input,pos))) + (1.0f-alpha)*curvature;

    // Determine gradient based on speed direction
    float3 gradient;
    if(speed < 0) {
        gradient = gradientMin;
    } else {
        gradient = gradientMax;
    }
    const float gradLength = length(gradient) > 1.0f ? 1.0f : length(gradient);

    // Stability CFL
    // max(fabs(speed*gradient.length()))
    float deltaT = 1.0f;

    // Update the level set function phi
    WRITE_FLOAT(phi_write, pos, READ_FLOAT(phi_read,pos) + deltaT*speed*gradLength);
}

__kernel void initializeLevelSetFunction(
        __write_only FLOAT_TYPE phi,
        __private int seedX,
        __private int seedY,
        __private int seedZ,
        __private float radius,
        __write_only CHAR_TYPE activeSet,
        __private char narrowBandDistance,
        __write_only FLOAT_TYPE phi_2,
        __write_only CHAR_TYPE borderSet
        ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    float dist = distance((float3)(seedX,seedY,seedZ), convert_float3(pos.xyz)) - radius;
    WRITE_FLOAT(phi, pos, dist);
    WRITE_FLOAT(phi_2, pos, dist);

    if(fabs(dist) < narrowBandDistance) {
        WRITE_INT(activeSet, pos, 1);
        if(fabs(dist) <= 1.0f) {
            WRITE_INT(borderSet, pos, 1);
        } else {
            WRITE_INT(borderSet, pos, 0);
        }
    } else {
        WRITE_INT(activeSet, pos, 0);
        WRITE_INT(borderSet, pos, 0);
    }
}

// Intialize 3D image to 0
__kernel void init3DImage(
    __write_only CHAR_TYPE image
    ) {
    WRITE_INT(image, (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0), 0);
}

__kernel void updateActiveSet(
        __global int * positions,
        __read_only FLOAT_TYPE phi,
        __write_only CHAR_TYPE activeSet,
        __private char narrowBandDistance,
        __read_only CHAR_TYPE previousActiveSet,
        __read_only CHAR_TYPE borderSet,
        __private int activeVoxels
        ) {
    int id = get_global_id(0) >= activeVoxels ? 0 : get_global_id(0);
    const int3 position = vload3(id, positions);
    // if voxel is border voxel
    bool isBorderVoxels = false, negativeFound = false, positiveFound = false;
    for(int x = -1; x < 2; x++) {
    for(int y = -1; y < 2; y++) {
    for(int z = -1; z < 2; z++) {
        int3 n = position + (int3)(x,y,z);
        if(READ_FLOAT(phi, n.xyzz) < 0.0f) {
            negativeFound = true;
        }else{
            positiveFound = true;
        }
    }}}
    isBorderVoxels = negativeFound && positiveFound;

    // Add all neighbors to activeSet
    if(isBorderVoxels) {
        if(READ_INT(borderSet, position.xyzz) == 0) { // not converged
            for(int x = -narrowBandDistance; x < narrowBandDistance; x++) {
            for(int y = -narrowBandDistance; y < narrowBandDistance; y++) {
            for(int z = -narrowBandDistance; z < narrowBandDistance; z++) {
                if(length((float3)(x,y,z)) > narrowBandDistance)
                    continue;

                int3 n = position + (int3)(x,y,z);
                    WRITE_INT(activeSet, n.xyzz, 1);
            }}}
        }
    }
}

__kernel void updateBorderSet(
        __write_only CHAR_TYPE borderSet,
        __read_only FLOAT_TYPE phi
        ) {
    const int3 position = {get_global_id(0), get_global_id(1), get_global_id(2)};
    bool isBorderVoxels = false, negativeFound = false, positiveFound = false;
    for(int x = -1; x < 2; x++) {
    for(int y = -1; y < 2; y++) {
    for(int z = -1; z < 2; z++) {
        int3 n = position + (int3)(x,y,z);
        if(READ_FLOAT(phi, n.xyzz) < 0.0f) {
            negativeFound = true;
        }else{
            positiveFound = true;
        }
    }}}
    isBorderVoxels = negativeFound && positiveFound;

    if(isBorderVoxels) {
        WRITE_INT(borderSet, position.xyzz, 1);
    }
}


/* Histogram Pyramids */

__constant int4 cubeOffsets2D[4] = {
    {0, 0, 0, 0},
    {0, 1, 0, 0},
    {1, 0, 0, 0},
    {1, 1, 0, 0},
};

__constant int4 cubeOffsets[8] = {
    {0, 0, 0, 0},
    {1, 0, 0, 0},
    {0, 0, 1, 0},
    {1, 0, 1, 0},
    {0, 1, 0, 0},
    {1, 1, 0, 0},
    {0, 1, 1, 0},
    {1, 1, 1, 0},
};

__kernel void constructHPLevel3D(
    __read_only image3d_t readHistoPyramid,
    __write_only image3d_t writeHistoPyramid
    ) { 

    int4 writePos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    int4 readPos = writePos*2;
    int writeValue = read_imagei(readHistoPyramid, hpSampler, readPos).x + // 0
    read_imagei(readHistoPyramid, hpSampler, readPos+cubeOffsets[1]).x + // 1
    read_imagei(readHistoPyramid, hpSampler, readPos+cubeOffsets[2]).x + // 2
    read_imagei(readHistoPyramid, hpSampler, readPos+cubeOffsets[3]).x + // 3
    read_imagei(readHistoPyramid, hpSampler, readPos+cubeOffsets[4]).x + // 4
    read_imagei(readHistoPyramid, hpSampler, readPos+cubeOffsets[5]).x + // 5
    read_imagei(readHistoPyramid, hpSampler, readPos+cubeOffsets[6]).x + // 6
    read_imagei(readHistoPyramid, hpSampler, readPos+cubeOffsets[7]).x; // 7

    write_imagei(writeHistoPyramid, writePos, writeValue);
}

__kernel void constructHPLevel2D(
    __read_only image2d_t readHistoPyramid,
    __write_only image2d_t writeHistoPyramid
    ) { 

    int2 writePos = {get_global_id(0), get_global_id(1)};
    int2 readPos = writePos*2;
    int writeValue = 
        read_imagei(readHistoPyramid, hpSampler, readPos).x + 
        read_imagei(readHistoPyramid, hpSampler, readPos+(int2)(1,0)).x + 
        read_imagei(readHistoPyramid, hpSampler, readPos+(int2)(0,1)).x + 
        read_imagei(readHistoPyramid, hpSampler, readPos+(int2)(1,1)).x;

    write_imagei(writeHistoPyramid, writePos, writeValue);
}

int3 scanHPLevel2D(int target, __read_only image2d_t hp, int3 current) {

    int4 neighbors = {
        read_imagei(hp, hpSampler, current.xy).x,
        read_imagei(hp, hpSampler, current.xy + (int2)(0,1)).x,
        read_imagei(hp, hpSampler, current.xy + (int2)(1,0)).x,
        0
    };

    int acc = current.z + neighbors.s0;
    int4 cmp;
    cmp.s0 = acc <= target;
    acc += neighbors.s1;
    cmp.s1 = acc <= target;
    acc += neighbors.s2;
    cmp.s2 = acc <= target;

    current += cubeOffsets2D[(cmp.s0+cmp.s1+cmp.s2)].xyz;
    current.x = current.x*2;
    current.y = current.y*2;
    current.z = current.z +
    cmp.s0*neighbors.s0 +
    cmp.s1*neighbors.s1 +
    cmp.s2*neighbors.s2; 
    return current;

}


int4 scanHPLevel3D(int target, __read_only image3d_t hp, int4 current) {

    int8 neighbors = {
        read_imagei(hp, hpSampler, current).x,
        read_imagei(hp, hpSampler, current + cubeOffsets[1]).x,
        read_imagei(hp, hpSampler, current + cubeOffsets[2]).x,
        read_imagei(hp, hpSampler, current + cubeOffsets[3]).x,
        read_imagei(hp, hpSampler, current + cubeOffsets[4]).x,
        read_imagei(hp, hpSampler, current + cubeOffsets[5]).x,
        read_imagei(hp, hpSampler, current + cubeOffsets[6]).x,
        0
    };

    int acc = current.s3 + neighbors.s0;
    int8 cmp;
    cmp.s0 = acc <= target;
    acc += neighbors.s1;
    cmp.s1 = acc <= target;
    acc += neighbors.s2;
    cmp.s2 = acc <= target;
    acc += neighbors.s3;
    cmp.s3 = acc <= target;
    acc += neighbors.s4;
    cmp.s4 = acc <= target;
    acc += neighbors.s5;
    cmp.s5 = acc <= target;
    acc += neighbors.s6;
    cmp.s6 = acc <= target;


    current += cubeOffsets[(cmp.s0+cmp.s1+cmp.s2+cmp.s3+cmp.s4+cmp.s5+cmp.s6)];
    current.s0 = current.s0*2;
    current.s1 = current.s1*2;
    current.s2 = current.s2*2;
    current.s3 = current.s3 +
    cmp.s0*neighbors.s0 +
    cmp.s1*neighbors.s1 +
    cmp.s2*neighbors.s2 +
    cmp.s3*neighbors.s3 +
    cmp.s4*neighbors.s4 +
    cmp.s5*neighbors.s5 +
    cmp.s6*neighbors.s6; 
    return current;

}

int4 traverseHP3D(
    int target,
    int HP_SIZE,
    image3d_t hp0,
    image3d_t hp1,
    image3d_t hp2,
    image3d_t hp3,
    image3d_t hp4,
    image3d_t hp5,
    image3d_t hp6,
    image3d_t hp7,
    image3d_t hp8,
    image3d_t hp9
    ) {
    int4 position = {0,0,0,0}; // x,y,z,sum
    if(HP_SIZE > 512)
    position = scanHPLevel3D(target, hp9, position);
    if(HP_SIZE > 256)
    position = scanHPLevel3D(target, hp8, position);
    if(HP_SIZE > 128)
    position = scanHPLevel3D(target, hp7, position);
    if(HP_SIZE > 64)
    position = scanHPLevel3D(target, hp6, position);
    if(HP_SIZE > 32)
    position = scanHPLevel3D(target, hp5, position);
    if(HP_SIZE > 16)
    position = scanHPLevel3D(target, hp4, position);
    if(HP_SIZE > 8)
    position = scanHPLevel3D(target, hp3, position);
    position = scanHPLevel3D(target, hp2, position);
    position = scanHPLevel3D(target, hp1, position);
    position = scanHPLevel3D(target, hp0, position);
    position.x = position.x / 2;
    position.y = position.y / 2;
    position.z = position.z / 2;
    return position;
}

int2 traverseHP2D(
    int target,
    int HP_SIZE,
    image2d_t hp0,
    image2d_t hp1,
    image2d_t hp2,
    image2d_t hp3,
    image2d_t hp4,
    image2d_t hp5,
    image2d_t hp6,
    image2d_t hp7,
    image2d_t hp8,
    image2d_t hp9,
    image2d_t hp10,
    image2d_t hp11,
    image2d_t hp12,
    image2d_t hp13
    ) {
    int3 position = {0,0,0};
    if(HP_SIZE > 8192)
    position = scanHPLevel2D(target, hp13, position);
    if(HP_SIZE > 4096)
    position = scanHPLevel2D(target, hp12, position);
    if(HP_SIZE > 2048)
    position = scanHPLevel2D(target, hp11, position);
    if(HP_SIZE > 1024)
    position = scanHPLevel2D(target, hp10, position);
    if(HP_SIZE > 512)
    position = scanHPLevel2D(target, hp9, position);
    if(HP_SIZE > 256)
    position = scanHPLevel2D(target, hp8, position);
    if(HP_SIZE > 128)
    position = scanHPLevel2D(target, hp7, position);
    if(HP_SIZE > 64)
    position = scanHPLevel2D(target, hp6, position);
    if(HP_SIZE > 32)
    position = scanHPLevel2D(target, hp5, position);
    if(HP_SIZE > 16)
    position = scanHPLevel2D(target, hp4, position);
    if(HP_SIZE > 8)
    position = scanHPLevel2D(target, hp3, position);
    position = scanHPLevel2D(target, hp2, position);
    position = scanHPLevel2D(target, hp1, position);
    position = scanHPLevel2D(target, hp0, position);
    position.x = position.x / 2;
    position.y = position.y / 2;
    return position.xy;
}


__kernel void createPositions3D(
        __global int * positions,
        __private int HP_SIZE,
        __private int sum,
        __read_only image3d_t hp0, // Largest HP
        __read_only image3d_t hp1,
        __read_only image3d_t hp2,
        __read_only image3d_t hp3,
        __read_only image3d_t hp4,
        __read_only image3d_t hp5
        ,__read_only image3d_t hp6
        ,__read_only image3d_t hp7
        ,__read_only image3d_t hp8
        ,__read_only image3d_t hp9
    ) {
    int target = get_global_id(0);
    if(target >= sum)
        target = 0;
    int4 pos = traverseHP3D(target,HP_SIZE,hp0,hp1,hp2,hp3,hp4,hp5,hp6,hp7,hp8,hp9);
    vstore3(pos.xyz, target, positions);
}

__kernel void createPositions2D(
        __global int * positions,
        __private int HP_SIZE,
        __private int sum,
        __read_only image2d_t hp0, // Largest HP
        __read_only image2d_t hp1,
        __read_only image2d_t hp2,
        __read_only image2d_t hp3,
        __read_only image2d_t hp4,
        __read_only image2d_t hp5
        ,__read_only image2d_t hp6
        ,__read_only image2d_t hp7
        ,__read_only image2d_t hp8
        ,__read_only image2d_t hp9
        ,__read_only image2d_t hp10
        ,__read_only image2d_t hp11
        ,__read_only image2d_t hp12
        ,__read_only image2d_t hp13
    ) {
    int target = get_global_id(0);
    if(target >= sum)
        target = 0;
    int2 pos = traverseHP2D(target,HP_SIZE,hp0,hp1,hp2,hp3,hp4,hp5,hp6,hp7,hp8,hp9,hp10,hp11,hp12,hp13);
    vstore2(pos, target, positions);
}
