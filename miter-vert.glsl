precision highp float;

attribute vec2 aCoord, bCoord, nextCoord, prevCoord;
attribute vec4 aColor, bColor;
attribute float lineEnd, lineTop;

uniform vec2 scale, translate, scaleRatio;
uniform float thickness, pixelRatio, id;
uniform vec4 viewport;
uniform float miterLimit, dashLength, miterMode;

varying vec4 fragColor;
varying vec4 startCutoff, endCutoff;
varying vec2 tangent;
varying vec2 startCoord, endCoord;
varying float enableStartMiter, enableEndMiter;

const float MAX_LINES = 256.;
const float REVERSE_THRESHOLD = -.875;
const float MIN_DIST = 1.;

//TODO: possible optimizations: avoid overcalculating all for vertices and calc just one instead
//TODO: precalculate dot products, normalize things etc.

float distToLine(vec2 p, vec2 a, vec2 b) {
	vec2 diff = b - a;
	vec2 perp = normalize(vec2(-diff.y, diff.x));
	return dot(p - a, perp);
}

void main() {
	vec2 aCoord = aCoord, bCoord = bCoord, prevCoord = prevCoord, nextCoord = nextCoord;
	vec2 normalWidth = thickness / scaleRatio;

	float lineStart = 1. - lineEnd;
	float lineBot = 1. - lineTop;
	float depth = (MAX_LINES - 1. - id) / MAX_LINES;

	fragColor = (lineStart * aColor + lineEnd * bColor) / 255.;

	if (aCoord == prevCoord) prevCoord = aCoord + normalize(bCoord - aCoord);
	if (bCoord == nextCoord) nextCoord = bCoord - normalize(bCoord - aCoord);

	vec2 prevDiff = aCoord - prevCoord;
	vec2 currDiff = bCoord - aCoord;
	vec2 nextDiff = nextCoord - bCoord;

	vec2 prevDirection = normalize(prevDiff);
	vec2 currDirection = normalize(currDiff);
	vec2 nextDirection = normalize(nextDiff);

	vec2 prevTangent = normalize(prevDiff * scaleRatio);
	vec2 currTangent = normalize(currDiff * scaleRatio);
	vec2 nextTangent = normalize(nextDiff * scaleRatio);

	vec2 prevNormal = vec2(-prevTangent.y, prevTangent.x);
	vec2 currNormal = vec2(-currTangent.y, currTangent.x);
	vec2 nextNormal = vec2(-nextTangent.y, nextTangent.x);

	vec2 startJoinDirection = normalize(prevTangent - currTangent);
	vec2 endJoinDirection = normalize(currTangent - nextTangent);

	//collapsed/unidirectional segment cases
	if (prevDirection == currDirection) {
		startJoinDirection = currNormal;
	}
	if (nextDirection == currDirection) {
		endJoinDirection = currNormal;
	}
	if (aCoord == bCoord) {
		endJoinDirection = startJoinDirection;
		currNormal = prevNormal;
		currTangent = prevTangent;
	}

	tangent = currTangent;

	//calculate join shifts relative to normals
	float startJoinShift = dot(currNormal, startJoinDirection);
	float endJoinShift = dot(currNormal, endJoinDirection);

	float startMiterRatio = abs(1. / startJoinShift);
	float endMiterRatio = abs(1. / endJoinShift);

	vec2 startJoin = startJoinDirection * startMiterRatio;
	vec2 endJoin = endJoinDirection * endMiterRatio;

	vec2 startTopJoin, startBotJoin, endTopJoin, endBotJoin;
	startTopJoin = sign(startJoinShift) * startJoin * .5;
	startBotJoin = -startTopJoin;

	endTopJoin = sign(endJoinShift) * endJoin * .5;
	endBotJoin = -endTopJoin;

	vec2 aTopCoord = aCoord + normalWidth * startTopJoin;
	vec2 bTopCoord = bCoord + normalWidth * endTopJoin;
	vec2 aBotCoord = aCoord + normalWidth * startBotJoin;
	vec2 bBotCoord = bCoord + normalWidth * endBotJoin;

	//miter anti-clipping
	float baClipping = distToLine(bCoord, aCoord, aBotCoord) / dot(normalize(normalWidth * endBotJoin), normalize(normalWidth.yx * vec2(-startBotJoin.y, startBotJoin.x)));
	float abClipping = distToLine(aCoord, bCoord, bTopCoord) / dot(normalize(normalWidth * startBotJoin), normalize(normalWidth.yx * vec2(-endBotJoin.y, endBotJoin.x)));

	//prevent close to reverse direction switch
	bool prevReverse = dot(currTangent, prevTangent) <= REVERSE_THRESHOLD && abs(dot(currTangent, prevNormal)) * min(length(prevDiff), length(currDiff)) <  length(normalWidth * currNormal);
	bool nextReverse = dot(currTangent, nextTangent) <= REVERSE_THRESHOLD && abs(dot(currTangent, nextNormal)) * min(length(nextDiff), length(currDiff)) <  length(normalWidth * currNormal);

	if (prevReverse) {
		//make join rectangular
		vec2 miterShift = normalWidth * startJoinDirection * miterLimit * .5;
		float normalAdjust = 1. - min(miterLimit / startMiterRatio, 1.);
		aBotCoord = aCoord + miterShift - normalAdjust * normalWidth * currNormal * .5;
		aTopCoord = aCoord + miterShift + normalAdjust * normalWidth * currNormal * .5;
	}
	else if (!nextReverse && baClipping > 0. && baClipping < length(normalWidth * endBotJoin)) {
		//handle miter clipping
		bTopCoord -= normalWidth * endTopJoin;
		bTopCoord += normalize(endTopJoin * normalWidth) * baClipping;
	}

	if (nextReverse) {
		//make join rectangular
		vec2 miterShift = normalWidth * endJoinDirection * miterLimit * .5;
		float normalAdjust = 1. - min(miterLimit / endMiterRatio, 1.);
		bBotCoord = bCoord + miterShift - normalAdjust * normalWidth * currNormal * .5;
		bTopCoord = bCoord + miterShift + normalAdjust * normalWidth * currNormal * .5;
	}
	else if (!prevReverse && abClipping > 0. && abClipping < length(normalWidth * startBotJoin)) {
		//handle miter clipping
		aBotCoord -= normalWidth * startBotJoin;
		aBotCoord += normalize(startBotJoin * normalWidth) * abClipping;
	}

	vec2 aTopPosition = (aTopCoord + translate) * scale;
	vec2 aBotPosition = (aBotCoord + translate) * scale;

	vec2 bTopPosition = (bTopCoord + translate) * scale;
	vec2 bBotPosition = (bBotCoord + translate) * scale;

	//position is normalized 0..1 coord on the screen
	vec2 position = (aTopPosition * lineTop + aBotPosition * lineBot) * lineStart + (bTopPosition * lineTop + bBotPosition * lineBot) * lineEnd;

	startCoord = (aCoord + translate) * scaleRatio + viewport.xy;
	endCoord = (bCoord + translate) * scaleRatio + viewport.xy;

	gl_Position = vec4(position  * 2.0 - 1.0, depth, 1);

	enableStartMiter = step(dot(currTangent, prevTangent), .5);
	enableEndMiter = step(dot(currTangent, nextTangent), .5);

	//bevel miter cutoffs
	if (miterMode == 1.) {
		if (enableStartMiter == 1.) {
			vec2 startMiterWidth = vec2(startJoinDirection) * thickness * miterLimit * .5;
			startCutoff = vec4(aCoord, aCoord);
			startCutoff.zw += vec2(-startJoinDirection.y, startJoinDirection.x) / scaleRatio;
			startCutoff = (startCutoff + translate.xyxy) * scaleRatio.xyxy;
			startCutoff += viewport.xyxy;
			startCutoff += startMiterWidth.xyxy;
		}

		if (enableEndMiter == 1.) {
			vec2 endMiterWidth = vec2(endJoinDirection) * thickness * miterLimit * .5;
			endCutoff = vec4(bCoord, bCoord);
			endCutoff.zw += vec2(-endJoinDirection.y, endJoinDirection.x)  / scaleRatio;
			endCutoff = (endCutoff + translate.xyxy) * scaleRatio.xyxy;
			endCutoff += viewport.xyxy;
			endCutoff += endMiterWidth.xyxy;
		}
	}

	//round miter cutoffs
	else if (miterMode == 2.) {
		if (enableStartMiter == 1.) {
			vec2 startMiterWidth = vec2(startJoinDirection) * thickness * abs(dot(startJoinDirection, currNormal)) * .5;
			startCutoff = vec4(aCoord, aCoord);
			startCutoff.zw += vec2(-startJoinDirection.y, startJoinDirection.x) / scaleRatio;
			startCutoff = (startCutoff + translate.xyxy) * scaleRatio.xyxy;
			startCutoff += viewport.xyxy;
			startCutoff += startMiterWidth.xyxy;
		}

		if (enableEndMiter == 1.) {
			vec2 endMiterWidth = vec2(endJoinDirection) * thickness * abs(dot(endJoinDirection, currNormal)) * .5;
			endCutoff = vec4(bCoord, bCoord);
			endCutoff.zw += vec2(-endJoinDirection.y, endJoinDirection.x)  / scaleRatio;
			endCutoff = (endCutoff + translate.xyxy) * scaleRatio.xyxy;
			endCutoff += viewport.xyxy;
			endCutoff += endMiterWidth.xyxy;
		}
	}
}