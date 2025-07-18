const vec3 ozoneAbsorption = vec3(6.6e-6,8.0e-6,0.2e-6);
const vec3 pureRayleighBeta = vec3(3.2e-6, 9.1e-6, 29.6e-6);
const vec3 rayleighBeta = pureRayleighBeta + ozoneAbsorption;
const float mieBeta = 2.1e-5;
const vec3 totalBeta = rayleighBeta + mieBeta;
const float rayLeighScaledHeight = 18500.0;
const float mieScaledHeight = 1200.0;
const vec2 scaledHeight = vec2(rayLeighScaledHeight, mieScaledHeight);
const float mieG = 0.76;
const float mieG2 = mieG * mieG;

const float earthRadius = 6371000.0;
const float atmosphereHeight = earthRadius + 100000.0;
const float sunRadius = 0.02;
const vec2 earthScaledHeight = 1.44269502 * earthRadius / scaledHeight;

vec4 planetIntersectionData(vec3 worldPos, vec3 worldDir) {
    worldPos.y += max(300.0 + earthRadius, cameraPosition.y + WORLD_BASIC_HEIGHT + earthRadius);
    float R2 = dot(worldPos, worldPos);
    float RdotP = dot(worldPos, worldDir);
    float RdotP2 = RdotP * RdotP - R2;
    float d = sqrt(RdotP2 + earthRadius * earthRadius);
    float rayHeight = sqrt(R2 + RdotP * abs(RdotP));
    float intersection = max(-1.0, -RdotP - d);
    float skyWeight = clamp(rayHeight / 300.0 - earthRadius / 300.0, 0.0, 1.0);
    return vec4(RdotP, RdotP2, intersection, skyWeight * skyWeight);
}

float rayleighPhase(float cosAngle) {
    const float rayleighFactor = (1.0 / (4.0 * PI)) * (8.0 / 10.0);
    return 12.0 / 5.0 * rayleighFactor + (0.5 * rayleighFactor * cosAngle);
}

float miePhase(float cosAngle, float g, float g2) {
    float x = inversesqrt(1.0 + g2 - 2.0 * g * cosAngle);
    return (3.0 / (8.0 * PI)) * ((1.0 - g2) * (1.0 + cosAngle * cosAngle)) / (2.0 + g2) * x * x * x;
}

float miePhase(float cosAngle) {
    float x = inversesqrt(1.0 + mieG2 - 2.0 * mieG * cosAngle);
    return (3.0 / (8.0 * PI)) * ((1.0 - mieG2) * (1.0 + cosAngle * cosAngle)) / (2.0 + mieG2) * x * x * x;
}

// https://www.shadertoy.com/view/WdKSRm
vec2 chapmanOpticalDepth(float originHeight, vec2 c, vec2 cExpH, float cosZenith) {
    cExpH *= scaledHeight * 1.44269502 / (c * abs(cosZenith) + 1.0);
    if (cosZenith < 0.0) {
        float sinZenith2 = 1.0 - cosZenith * cosZenith;
        float x0 = sinZenith2 * inversesqrt(sinZenith2) * originHeight;
        cExpH = 2.0 * sqrt(scaledHeight * 1.44269502) * x0 * inversesqrt(x0) * exp2(earthScaledHeight - x0 / scaledHeight) - cExpH;
    }
    return cExpH;
}

vec3 sampleInScattering(float originHeight, vec2 c, vec2 cExpH, float cosZenith) {
    vec2 opticalDepth = chapmanOpticalDepth(originHeight, c, cExpH, cosZenith);

    vec3 inScattering = exp2(-opticalDepth.x * rayleighBeta - opticalDepth.y * rainyMieBeta);

    return inScattering;
}

// https://www.shadertoy.com/view/WdKSRm
void chapmanOpticalDepthDoubleSide(float originHeight, vec2 c, vec2 cExpH, float cosZenith, out vec2 sunOpticalDepth, out vec2 moonOpticalDepth) {
    const vec2 baseWeight = scaledHeight * 1.44269502;

    cExpH /= c * abs(cosZenith) + 1.0;
    float sinZenith2 = 1.0 - cosZenith * cosZenith;
    float x0 = sinZenith2 * inversesqrt(sinZenith2) * originHeight;
    vec2 c0 = 2.0 * inversesqrt(scaledHeight * 1.44269502) * x0 * inversesqrt(x0) * exp2(earthScaledHeight - x0 / scaledHeight) - cExpH;

    uint direction = floatBitsToUint(cosZenith) & 0x80000000u;
    cExpH = uintBitsToFloat(floatBitsToUint(cExpH) | direction);
    c0 = uintBitsToFloat(floatBitsToUint(c0) | direction);

    sunOpticalDepth = baseWeight * max(cExpH, -c0);
    moonOpticalDepth = baseWeight * max(-cExpH, c0);
}

void sampleInScatteringDoubleSide(float originHeight, vec2 c, vec2 cExpH, float cosZenith, out vec3 sunInScattering, out vec3 moonInScattering) {
    vec2 sunOpticalDepth, moonOpticalDepth;
    chapmanOpticalDepthDoubleSide(originHeight, c, cExpH, cosZenith, sunOpticalDepth, moonOpticalDepth);

    sunInScattering = exp2(-sunOpticalDepth.x * rayleighBeta - sunOpticalDepth.y * rainyMieBeta);
    moonInScattering = exp2(-moonOpticalDepth.x * rayleighBeta - moonOpticalDepth.y * rainyMieBeta);
}

vec3 singleAtmosphereScattering(vec3 skyLightColor, vec3 worldPos, vec3 worldDir, vec3 sunDir, vec4 intersectionData, float sunLightStrength, out vec3 atmosphere) {
    float sunsetBoostFactor = 1.0;
    atmosphere = vec3(0.0);
    vec3 result = skyLightColor;

    if (intersectionData.y > -atmosphereHeight * atmosphereHeight) {
        vec3 originPos = worldPos;
        originPos.y += max(cameraPosition.y + WORLD_BASIC_HEIGHT + earthRadius, 300.0 + earthRadius);

        float b = intersectionData.x;
        float deltaAtmos = intersectionData.y + atmosphereHeight * atmosphereHeight;
        float d = deltaAtmos * inversesqrt(deltaAtmos);
        float atmosphereLength = -b + d;
        if (atmosphereLength > 0.0) {
            float groundLength = intersectionData.z;
            float hitSky = clamp(-1e+10 * groundLength, 0.0, 1.0);
            float originHeight2 = dot(originPos, originPos);
            groundLength = max(groundLength, uintBitsToFloat(floatBitsToUint(-sqrt(originHeight2 - earthRadius * earthRadius)) ^ (floatBitsToUint(groundLength) & 0x80000000u)));
            atmosphereLength = mix(groundLength, atmosphereLength, intersectionData.w);
            b += d;
            b = min(0.0, b);
            originPos -= worldDir * b;
            atmosphereLength += b;
            vec3 samplePosition = originPos;
            result *= intersectionData.w;

            originHeight2 = dot(samplePosition, samplePosition);
            float originHeightInv = inversesqrt(originHeight2);
            float originHeight = originHeight2 * originHeightInv * 1.44269502;
            vec2 c = inversesqrt(originHeightInv) * inversesqrt(scaledHeight);
            vec2 prevRelativeDensity = exp2(earthScaledHeight - originHeight / scaledHeight);
            vec2 cExpH = c * prevRelativeDensity;

            vec3 atmosphereAbsorption = sampleInScattering(originHeight, c, cExpH, dot(worldDir, samplePosition) * originHeightInv);
            result *= atmosphereAbsorption;

            float originRdotP = dot(sunDir, samplePosition) * originHeightInv;
            vec3 originSunInScattering, originMoonInScattering;
            sampleInScatteringDoubleSide(originHeight, c, cExpH, originRdotP, originSunInScattering, originMoonInScattering);

            float sunCosAngle = dot(worldDir, sunDir);
            float sunRayleigh = rayleighPhase(sunCosAngle);
            float sunMie = miePhase(sunCosAngle);
            float sunHeight = sunDir.y;
            float twilightRange = 0.15;
            float twilightHeight = sunHeight + twilightRange;
            float sunsetBoost = 
            exp(-sunHeight * sunHeight * 200.0) * 0.0 + 
            exp(-twilightHeight * twilightHeight * 380.0) * 10.0;
            float sunsetBoostFactor = 1.0 + clamp(sunsetBoost, 0.0, 3.0);
            vec3 viewToSun = normalize(sunDir - worldDir);
            float azimuthFactor = pow(max(dot(viewToSun, sunDir), 0.0), 4.0);
            sunsetBoost *= mix(0.3, 1.0, azimuthFactor);
            float moonRayleigh = rayleighPhase(-sunCosAngle) * nightBrightness;
            float moonMie = miePhase(-sunCosAngle) * nightBrightness;

            vec3 prevRayleighInScattering = originSunInScattering * prevRelativeDensity.x * sunRayleigh + originMoonInScattering * prevRelativeDensity.x * moonRayleigh;
            vec3 prevMieInScattering = originSunInScattering * prevRelativeDensity.y * sunMie + originMoonInScattering * prevRelativeDensity.y * moonMie;

            vec2 opticalDepth = vec2(0.0);
            vec3 totalRayleighInScattering = vec3(0.0);
            vec3 totalMieInScattering = vec3(0.0);

            const float viewSampleStepScale = 4.0;
            float stepUnit = atmosphereLength / ((ATMOSPHERE_VIEW_SAMPLE * 0.5 - 0.5 + viewSampleStepScale) * ATMOSPHERE_VIEW_SAMPLE);
            float stepLength = stepUnit * (viewSampleStepScale - 1.0);

            for (int i = 0; i < ATMOSPHERE_VIEW_SAMPLE; i++) {
                stepLength += stepUnit;
                samplePosition += worldDir * stepLength;
                float sampleHeight2 = dot(samplePosition, samplePosition);

                float sampleHeightInv = inversesqrt(sampleHeight2);
                float sampleRdotP = dot(sunDir, samplePosition) * sampleHeightInv;
                float sampleHeight = sampleHeight2 * sampleHeightInv * 1.44269502;
                vec2 c = inversesqrt(sampleHeightInv) * inversesqrt(scaledHeight);
                vec2 currRelativeDensity = exp2(earthScaledHeight - sampleHeight / scaledHeight);
                vec2 cExpH = c * currRelativeDensity;

                opticalDepth += (0.5 * 1.44269502 * stepLength) * (prevRelativeDensity + currRelativeDensity);
                prevRelativeDensity = currRelativeDensity;

                vec2 sunOpticalDepth, moonOpticalDepth;
                chapmanOpticalDepthDoubleSide(sampleHeight, c, cExpH, sampleRdotP, sunOpticalDepth, moonOpticalDepth);
                sunOpticalDepth += opticalDepth;
                moonOpticalDepth += opticalDepth;

                vec3 currSunInScattering = exp2(-sunOpticalDepth.x * rayleighBeta - sunOpticalDepth.y * rainyMieBeta);
                vec3 currMoonInScattering = exp2(-moonOpticalDepth.x * rayleighBeta - moonOpticalDepth.y * rainyMieBeta);

                vec3 currRayleighInScattering = currSunInScattering * prevRelativeDensity.x * sunRayleigh + currMoonInScattering * prevRelativeDensity.x * moonRayleigh;
                totalRayleighInScattering += stepLength * (prevRayleighInScattering + currRayleighInScattering);
                prevRayleighInScattering = currRayleighInScattering;
                vec3 currMieInScattering = currSunInScattering * prevRelativeDensity.y * sunMie + currMoonInScattering * prevRelativeDensity.y * moonMie;
                totalMieInScattering += stepLength * (prevMieInScattering + currMieInScattering);
                prevMieInScattering = currMieInScattering;
            }

            vec3 totalInScattering = (totalRayleighInScattering * pureRayleighBeta + totalMieInScattering * rainyMieBeta);
            totalInScattering *= 0.5 * sunsetBoostFactor;
            
            

            atmosphere = totalInScattering * sunLightStrength;

            result += atmosphere;
        }
    }
    return result;
}

vec3 atmosphereScatteringUp(float lightHeight, float sunLightStrength) {
    float playerHeight = max(cameraPosition.y + WORLD_BASIC_HEIGHT + earthRadius, 300.0 + earthRadius);

    float atmosphereLength = atmosphereHeight - playerHeight;
    vec3 result = vec3(0.0);
    if (atmosphereLength > 0.0) {
        vec2 c = playerHeight * inversesqrt(playerHeight) * inversesqrt(scaledHeight);
        vec2 prevRelativeDensity = exp2(earthScaledHeight - playerHeight / scaledHeight * 1.44269502);
        vec2 cExpH = c * prevRelativeDensity;
        vec3 originSunInScattering, originMoonInScattering;
        sampleInScatteringDoubleSide(playerHeight * 1.44269502, c, cExpH, lightHeight, originSunInScattering, originMoonInScattering);

        vec3 prevSunRayleighInScattering = originSunInScattering * prevRelativeDensity.x;
        vec3 prevSunMieInScattering = originSunInScattering * prevRelativeDensity.y;
        vec3 prevMoonRayleighInScattering = originMoonInScattering * prevRelativeDensity.x;
        vec3 prevMoonMieInScattering = originMoonInScattering * prevRelativeDensity.y;

        vec2 opticalDepth = vec2(0.0);
        vec3 totalSunRayleighInScattering = vec3(0.0);
        vec3 totalSunMieInScattering = vec3(0.0);
        vec3 totalMoonRayleighInScattering = vec3(0.0);
        vec3 totalMoonMieInScattering = vec3(0.0);

        const float viewSampleStepScale = 4.0;
        float stepUnit = atmosphereLength / ((ATMOSPHERE_VIEW_SAMPLE * 0.5 - 0.5 + viewSampleStepScale) * ATMOSPHERE_VIEW_SAMPLE);
        float sampleHeight = playerHeight;
        float stepLength = stepUnit * (viewSampleStepScale - 1.0);

        for (int i = 0; i < ATMOSPHERE_VIEW_SAMPLE; i++) {
            stepLength += stepUnit;
            sampleHeight += stepLength;

            vec2 c = sampleHeight * inversesqrt(sampleHeight) * inversesqrt(scaledHeight);
            vec2 currRelativeDensity = exp2(earthScaledHeight - sampleHeight / scaledHeight * 1.44269502);
            vec2 cExpH = c * currRelativeDensity;

            opticalDepth += (0.5 * 1.44269502 * stepLength) * (prevRelativeDensity + currRelativeDensity);
            prevRelativeDensity = currRelativeDensity;

            vec2 sunOpticalDepth, moonOpticalDepth;
            chapmanOpticalDepthDoubleSide(sampleHeight * 1.44269502, c, cExpH, lightHeight, sunOpticalDepth, moonOpticalDepth);
            sunOpticalDepth += opticalDepth;
            moonOpticalDepth += opticalDepth;

            vec3 currSunInScattering = exp2(-sunOpticalDepth.x * rayleighBeta - sunOpticalDepth.y * rainyMieBeta);
            vec3 currSunRayleighInScattering = currSunInScattering * prevRelativeDensity.x;
            totalSunRayleighInScattering += stepLength * (prevSunRayleighInScattering + currSunRayleighInScattering);
            prevSunRayleighInScattering = currSunRayleighInScattering;
            vec3 currSunMieInScattering = currSunInScattering * prevRelativeDensity.y;
            totalSunMieInScattering += stepLength * (prevSunMieInScattering + currSunMieInScattering);
            prevSunMieInScattering = currSunMieInScattering;

            vec3 currMoonInScattering = exp2(-moonOpticalDepth.x * rayleighBeta - moonOpticalDepth.y * rainyMieBeta);
            vec3 currMoonRayleighInScattering = currMoonInScattering * prevRelativeDensity.x;
            totalMoonRayleighInScattering += stepLength * (prevMoonRayleighInScattering + currMoonRayleighInScattering);
            prevMoonRayleighInScattering = currMoonRayleighInScattering;
            vec3 currMoonMieInScattering = currMoonInScattering * prevRelativeDensity.y;
            totalMoonMieInScattering += stepLength * (prevMoonMieInScattering + currMoonMieInScattering);
            prevMoonMieInScattering = currMoonMieInScattering;
        }

        totalSunRayleighInScattering *= rayleighPhase(lightHeight);
        totalSunMieInScattering *= miePhase(lightHeight);
        float nightBrightness = mix(NIGHT_BRIGHTNESS, NIGHT_VISION_BRIGHTNESS, nightVision);
        totalMoonRayleighInScattering *= rayleighPhase(-lightHeight) * nightBrightness;
        totalMoonMieInScattering *= miePhase(-lightHeight) * nightBrightness;

        vec3 totalRayleighInScattering = totalSunRayleighInScattering + totalMoonRayleighInScattering;
        vec3 totalMieInScattering = totalSunMieInScattering + totalMoonMieInScattering;

        vec3 totalInScattering = totalRayleighInScattering * pureRayleighBeta + totalMieInScattering * rainyMieBeta;
        totalInScattering *= 0.5;

        result = totalInScattering * sunLightStrength;
    }
    return result;
}

vec3 solidAtmosphereScattering(vec3 color, vec3 worldDir, vec3 skyColor, float worldDepth, float skyLight) {
    const float a = 0.1;
    vec3 absorption = exp2(-vec3(worldDepth * rainyMieBeta * (1.0 + RF_DENSITY * 3.0 * weatherStrength * weatherStrength) * 10.0 * 1.44269502 * exp2((-WORLD_BASIC_HEIGHT - cameraPosition.y) / 1200.0)));
    vec3 scatteringColor = skyLight * (
        0.1 * skyColor * (1.0 - weatherStrength * (1.0 - RF_SKY_BRIGHTNESS)) +
        sunColor * miePhase(dot(worldDir, shadowDirection), 0.4, 0.16) * (1.0 - weatherStrength * (1.0 - RF_SUN_BRIGHTNESS))
    );
    vec3 scattering = scatteringColor * (1.0 - absorption) * 30.0;
    return color * absorption + scattering;
}

float blindnessFactor = max(darknessFactor * 0.5, blindness);
vec3 waterAbsorptionBeta = vec3(WATER_ABSORPTION_R, WATER_ABSORPTION_G, WATER_ABSORPTION_B) + blindnessFactor;
float lavaAbsorptionBeta = 1.0 * LAVA_FOG_DENSITY + blindnessFactor;
float snowAbsorptionBeta = 2.0 * SNOW_FOG_DENSITY + blindnessFactor;
float netherAbsorptionBeta = 0.01 * NETHER_FOG_DENSITY + blindnessFactor;
float endAbsorptionBeta = 0.01 * END_FOG_DENSITY + blindnessFactor;

float airAbsorption(float depth) {
    return exp(-blindnessFactor * depth);
}

vec3 waterFogAbsorption(float waterDepth) {
    return exp(-waterDepth * waterAbsorptionBeta);
}

vec3 waterFogScattering(vec3 worldDir, vec3 skyColor, float waterDepth, float skyLight) {
    float miePhase = miePhase(worldDir.y, 0.4, 0.16);
    vec3 scattering = skyLight * miePhase * skyColor * (1.0 - exp(-waterDepth * waterAbsorptionBeta)) * exp(-16.0 * (1.0 - skyLight) * waterAbsorptionBeta);
    return scattering;
}

vec3 waterFogTotal(vec3 targetColor, vec3 worldDir, vec3 skyColor, float waterDepth, float skyLight) {
    targetColor *= waterFogAbsorption(waterDepth);
    targetColor += waterFogScattering(worldDir, skyColor, waterDepth, skyLight);
    return targetColor;
}

float lavaFogAbsorption(float lavaDepth) {
    return exp(-lavaDepth * lavaAbsorptionBeta);
}

vec3 lavaFogScattering(float lavaDepth) {
    return vec3(1.0, 0.05, 0.0) * LAVA_FOG_BRIGHTNESS * 10.0 * (1.0 - exp(-lavaDepth * lavaAbsorptionBeta));
}

vec3 lavaFogTotal(vec3 targetColor, float lavaDepth) {
    targetColor *= lavaFogAbsorption(lavaDepth);
    targetColor += lavaFogScattering(lavaDepth);
    return targetColor;
}

float snowFogAbsorption(float snowDepth) {
    return exp(-snowDepth * snowAbsorptionBeta);
}

vec3 snowFogScattering(vec3 skyColor, float snowDepth, float skyLight) {
    vec3 scattering = (skyLight * skyLight * skyLight) * skyColor * (1.0 - exp(-snowDepth * snowAbsorptionBeta));
    return scattering;
}

vec3 snowFogTotal(vec3 targetColor, vec3 skyColor, float snowDepth, float skyLight) {
    targetColor *= snowFogAbsorption(snowDepth);
    targetColor += snowFogScattering(skyColor, snowDepth, skyLight);
    return targetColor;
}

float netherFogAbsorption(float netherDepth) {
    return exp(-netherDepth * netherAbsorptionBeta);
}

vec3 netherFogScattering(float netherDepth) {
    return NETHER_FOG_BRIGHTNESS * 5.0 * (1.0 - exp(-netherDepth * netherAbsorptionBeta)) * pow(fogColor, vec3(2.2));
}

vec3 netherFogTotal(vec3 targetColor, float netherDepth) {
    targetColor *= netherFogAbsorption(netherDepth);
    targetColor += netherFogScattering(netherDepth);
    return targetColor;
}

float endFogAbsorption(float endDepth) {
    return exp(-endDepth * endAbsorptionBeta);
}

vec3 endFogScattering(float endDepth) {
    return END_FOG_BRIGHTNESS * 0.1 * (1.0 - exp(-endDepth * endAbsorptionBeta)) * vec3(0.5, 0.2, 0.8);
}

vec3 endFogTotal(vec3 targetColor, float endDepth) {
    targetColor *= endFogAbsorption(endDepth);
    targetColor += endFogScattering(endDepth);
    return targetColor;
}
