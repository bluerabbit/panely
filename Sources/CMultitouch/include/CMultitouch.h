#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

// MultitouchSupport.framework（private）の構造体定義。
// レイアウトは Kyome22/OpenMultitouchSupport（MIT）の OpenMTInternal.h と同じ。
// フィールド名はこのプロジェクトで付け直している。
// 関数は dlsym で取得するため、ここでは型だけを定義する。

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef int MTPathStage;
enum {
    kMTPathStageNotTracking = 0,
    kMTPathStageStartInRange = 1,
    kMTPathStageHoverInRange = 2,
    kMTPathStageMakeTouch = 3,
    kMTPathStageTouching = 4,
    kMTPathStageBreakTouch = 5,
    kMTPathStageLingerInRange = 6,
    kMTPathStageOutOfRange = 7,
};

typedef struct {
    int frame;
    double timestamp;
    int identifier;          // pathIndex
    MTPathStage stage;
    int fingerID;
    int handID;
    MTVector normalizedVector;   // position は 0.0 ... 1.0（左下原点）
    float total;
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;     // 単位は mm
    int unknown14;
    int unknown15;
    float density;
} MTTouch;

typedef struct MTDevice *MTDeviceRef;

typedef void (*MTFrameCallbackFunction)(MTDeviceRef device, MTTouch touches[], int numTouches, double timestamp, int frame);

#endif
