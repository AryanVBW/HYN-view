/* esm.sh - three@0.177.0 */
import{Matrix3 as Oe,Vector2 as dt,Color as $e,mergeUniforms as lt,Vector3 as We,CubeUVReflectionMapping as mn,Mesh as xt,BoxGeometry as lr,ShaderMaterial as It,BackSide as mt,cloneUniforms as oi,Euler as fr,Matrix4 as Vt,ColorManagement as tt,SRGBTransfer as Ye,PlaneGeometry as dr,FrontSide as Zt,getUnlitUniformColorSpace as ur,IntType as pr,HalfFloatType as _n,UnsignedByteType as yt,FloatType as Dt,RGBAFormat as Tt,Plane as Br,EquirectangularReflectionMapping as yn,EquirectangularRefractionMapping as Nn,WebGLCubeRenderTarget as Gr,CubeReflectionMapping as Qt,CubeRefractionMapping as kt,OrthographicCamera as Hr,PerspectiveCamera as sn,NoToneMapping as At,MeshBasicMaterial as Vr,NoBlending as wt,WebGLRenderTarget as zt,BufferGeometry as hr,BufferAttribute as cn,LinearSRGBColorSpace as vn,LinearFilter as Bt,warnOnce as ln,Uint32BufferAttribute as kr,Uint16BufferAttribute as zr,arrayNeedsUint32 as Wr,Vector4 as ft,DataArrayTexture as mr,CubeTexture as Xr,Data3DTexture as Kr,LessEqualCompare as _r,DepthTexture as vr,Texture as gr,GLSL3 as si,PCFShadowMap as Sr,PCFSoftShadowMap as Yr,VSMShadowMap as Et,CustomToneMapping as qr,NeutralToneMapping as $r,AgXToneMapping as Zr,ACESFilmicToneMapping as Qr,CineonToneMapping as Jr,ReinhardToneMapping as jr,LinearToneMapping as ea,LinearTransfer as Er,AddOperation as ta,MixOperation as na,MultiplyOperation as ia,UniformsUtils as ra,DoubleSide as Mt,NormalBlending as fn,TangentSpaceNormalMap as aa,ObjectSpaceNormalMap as oa,Layers as sa,Frustum as Mr,MeshDepthMaterial as ca,RGBADepthPacking as la,MeshDistanceMaterial as fa,NearestFilter as $t,LessEqualDepth as dn,ReverseSubtractEquation as da,SubtractEquation as ua,AddEquation as Kt,OneMinusConstantAlphaFactor as pa,ConstantAlphaFactor as ha,OneMinusConstantColorFactor as ma,ConstantColorFactor as _a,OneMinusDstAlphaFactor as va,OneMinusDstColorFactor as ga,OneMinusSrcAlphaFactor as Sa,OneMinusSrcColorFactor as Ea,DstAlphaFactor as Ma,DstColorFactor as Ta,SrcAlphaSaturateFactor as xa,SrcAlphaFactor as Aa,SrcColorFactor as Ra,OneFactor as Ca,ZeroFactor as ba,NotEqualDepth as On,GreaterDepth as Fn,GreaterEqualDepth as Bn,EqualDepth as Gn,LessDepth as Hn,AlwaysDepth as Vn,NeverDepth as kn,CullFaceNone as Pa,CullFaceBack as ci,CullFaceFront as La,CustomBlending as Ua,MultiplyBlending as li,SubtractiveBlending as fi,AdditiveBlending as di,MinEquation as Da,MaxEquation as wa,MirroredRepeatWrapping as Ia,ClampToEdgeWrapping as ya,RepeatWrapping as Na,LinearMipmapLinearFilter as Yt,LinearMipmapNearestFilter as Mn,NearestMipmapLinearFilter as nn,NearestMipmapNearestFilter as Oa,NotEqualCompare as Fa,GreaterCompare as Ba,GreaterEqualCompare as Ga,EqualCompare as Ha,LessCompare as Va,AlwaysCompare as ka,NeverCompare as za,NoColorSpace as Ft,DepthStencilFormat as un,getByteLength as ui,DepthFormat as Qn,UnsignedIntType as Jt,UnsignedInt248Type as jt,UnsignedShortType as pn,createElementNS as Wa,UnsignedShort4444Type as Tr,UnsignedShort5551Type as xr,UnsignedInt5999Type as Xa,ByteType as Ka,ShortType as Ya,AlphaFormat as qa,RGBFormat as $a,RedFormat as Za,RedIntegerFormat as Ar,RGFormat as Qa,RGIntegerFormat as Rr,RGBAIntegerFormat as Cr,RGB_S3TC_DXT1_Format as Tn,RGBA_S3TC_DXT1_Format as xn,RGBA_S3TC_DXT3_Format as An,RGBA_S3TC_DXT5_Format as Rn,RGB_PVRTC_4BPPV1_Format as pi,RGB_PVRTC_2BPPV1_Format as hi,RGBA_PVRTC_4BPPV1_Format as mi,RGBA_PVRTC_2BPPV1_Format as _i,RGB_ETC1_Format as vi,RGB_ETC2_Format as gi,RGBA_ETC2_EAC_Format as Si,RGBA_ASTC_4x4_Format as Ei,RGBA_ASTC_5x4_Format as Mi,RGBA_ASTC_5x5_Format as Ti,RGBA_ASTC_6x5_Format as xi,RGBA_ASTC_6x6_Format as Ai,RGBA_ASTC_8x5_Format as Ri,RGBA_ASTC_8x6_Format as Ci,RGBA_ASTC_8x8_Format as bi,RGBA_ASTC_10x5_Format as Pi,RGBA_ASTC_10x6_Format as Li,RGBA_ASTC_10x8_Format as Ui,RGBA_ASTC_10x10_Format as Di,RGBA_ASTC_12x10_Format as wi,RGBA_ASTC_12x12_Format as Ii,RGBA_BPTC_Format as Cn,RGB_BPTC_SIGNED_Format as yi,RGB_BPTC_UNSIGNED_Format as Ni,RED_RGTC1_Format as Ja,SIGNED_RED_RGTC1_Format as Oi,RED_GREEN_RGTC2_Format as Fi,SIGNED_RED_GREEN_RGTC2_Format as Bi,EventDispatcher as ja,ArrayCamera as eo,WebXRController as bn,RAD2DEG as to,createCanvasElement as no,SRGBColorSpace as io,REVISION as ro,toNormalizedProjectionMatrix as ao,toReversedProjectionMatrix as oo,probeAsync as so,WebGLCoordinateSystem as co}from"./build/three.core.mjs";import{AdditiveAnimationBlendMode as kf,AlwaysStencilFunc as zf,AmbientLight as Wf,AnimationAction as Xf,AnimationClip as Kf,AnimationLoader as Yf,AnimationMixer as qf,AnimationObjectGroup as $f,AnimationUtils as Zf,ArcCurve as Qf,ArrowHelper as Jf,AttachedBindMode as jf,Audio as ed,AudioAnalyser as td,AudioContext as nd,AudioListener as id,AudioLoader as rd,AxesHelper as ad,BasicDepthPacking as od,BasicShadowMap as sd,BatchedMesh as cd,Bone as ld,BooleanKeyframeTrack as fd,Box2 as dd,Box3 as ud,Box3Helper as pd,BoxHelper as hd,BufferGeometryLoader as md,Cache as _d,Camera as vd,CameraHelper as gd,CanvasTexture as Sd,CapsuleGeometry as Ed,CatmullRomCurve3 as Md,CircleGeometry as Td,Clock as xd,ColorKeyframeTrack as Ad,CompressedArrayTexture as Rd,CompressedCubeTexture as Cd,CompressedTexture as bd,CompressedTextureLoader as Pd,ConeGeometry as Ld,Controls as Ud,CubeCamera as Dd,CubeTextureLoader as wd,CubicBezierCurve as Id,CubicBezierCurve3 as yd,CubicInterpolant as Nd,CullFaceFrontBack as Od,Curve as Fd,CurvePath as Bd,CylinderGeometry as Gd,Cylindrical as Hd,DataTexture as Vd,DataTextureLoader as kd,DataUtils as zd,DecrementStencilOp as Wd,DecrementWrapStencilOp as Xd,DefaultLoadingManager as Kd,DetachedBindMode as Yd,DirectionalLight as qd,DirectionalLightHelper as $d,DiscreteInterpolant as Zd,DodecahedronGeometry as Qd,DynamicCopyUsage as Jd,DynamicDrawUsage as jd,DynamicReadUsage as eu,EdgesGeometry as tu,EllipseCurve as nu,EqualStencilFunc as iu,ExtrudeGeometry as ru,FileLoader as au,Float16BufferAttribute as ou,Float32BufferAttribute as su,Fog as cu,FogExp2 as lu,FramebufferTexture as fu,FrustumArray as du,GLBufferAttribute as uu,GLSL1 as pu,GreaterEqualStencilFunc as hu,GreaterStencilFunc as mu,GridHelper as _u,Group as vu,HemisphereLight as gu,HemisphereLightHelper as Su,IcosahedronGeometry as Eu,ImageBitmapLoader as Mu,ImageLoader as Tu,ImageUtils as xu,IncrementStencilOp as Au,IncrementWrapStencilOp as Ru,InstancedBufferAttribute as Cu,InstancedBufferGeometry as bu,InstancedInterleavedBuffer as Pu,InstancedMesh as Lu,Int16BufferAttribute as Uu,Int32BufferAttribute as Du,Int8BufferAttribute as wu,InterleavedBuffer as Iu,InterleavedBufferAttribute as yu,Interpolant as Nu,InterpolateDiscrete as Ou,InterpolateLinear as Fu,InterpolateSmooth as Bu,InterpolationSamplingMode as Gu,InterpolationSamplingType as Hu,InvertStencilOp as Vu,KeepStencilOp as ku,KeyframeTrack as zu,LOD as Wu,LatheGeometry as Xu,LessEqualStencilFunc as Ku,LessStencilFunc as Yu,Light as qu,LightProbe as $u,Line as Zu,Line3 as Qu,LineBasicMaterial as Ju,LineCurve as ju,LineCurve3 as ep,LineDashedMaterial as tp,LineLoop as np,LineSegments as ip,LinearInterpolant as rp,LinearMipMapLinearFilter as ap,LinearMipMapNearestFilter as op,Loader as sp,LoaderUtils as cp,LoadingManager as lp,LoopOnce as fp,LoopPingPong as dp,LoopRepeat as up,MOUSE as pp,Material as hp,MaterialLoader as mp,MathUtils as _p,Matrix2 as vp,MeshLambertMaterial as gp,MeshMatcapMaterial as Sp,MeshNormalMaterial as Ep,MeshPhongMaterial as Mp,MeshPhysicalMaterial as Tp,MeshStandardMaterial as xp,MeshToonMaterial as Ap,NearestMipMapLinearFilter as Rp,NearestMipMapNearestFilter as Cp,NeverStencilFunc as bp,NormalAnimationBlendMode as Pp,NotEqualStencilFunc as Lp,NumberKeyframeTrack as Up,Object3D as Dp,ObjectLoader as wp,OctahedronGeometry as Ip,Path as yp,PlaneHelper as Np,PointLight as Op,PointLightHelper as Fp,Points as Bp,PointsMaterial as Gp,PolarGridHelper as Hp,PolyhedronGeometry as Vp,PositionalAudio as kp,PropertyBinding as zp,PropertyMixer as Wp,QuadraticBezierCurve as Xp,QuadraticBezierCurve3 as Kp,Quaternion as Yp,QuaternionKeyframeTrack as qp,QuaternionLinearInterpolant as $p,RGBDepthPacking as Zp,RGBIntegerFormat as Qp,RGDepthPacking as Jp,RawShaderMaterial as jp,Ray as eh,Raycaster as th,RectAreaLight as nh,RenderTarget as ih,RenderTarget3D as rh,ReplaceStencilOp as ah,RingGeometry as oh,Scene as sh,ShadowMaterial as ch,Shape as lh,ShapeGeometry as fh,ShapePath as dh,ShapeUtils as uh,Skeleton as ph,SkeletonHelper as hh,SkinnedMesh as mh,Source as _h,Sphere as vh,SphereGeometry as gh,Spherical as Sh,SphericalHarmonics3 as Eh,SplineCurve as Mh,SpotLight as Th,SpotLightHelper as xh,Sprite as Ah,SpriteMaterial as Rh,StaticCopyUsage as Ch,StaticDrawUsage as bh,StaticReadUsage as Ph,StereoCamera as Lh,StreamCopyUsage as Uh,StreamDrawUsage as Dh,StreamReadUsage as wh,StringKeyframeTrack as Ih,TOUCH as yh,TetrahedronGeometry as Nh,TextureLoader as Oh,TextureUtils as Fh,TimestampQuery as Bh,TorusGeometry as Gh,TorusKnotGeometry as Hh,Triangle as Vh,TriangleFanDrawMode as kh,TriangleStripDrawMode as zh,TrianglesDrawMode as Wh,TubeGeometry as Xh,UVMapping as Kh,Uint8BufferAttribute as Yh,Uint8ClampedBufferAttribute as qh,Uniform as $h,UniformsGroup as Zh,VectorKeyframeTrack as Qh,VideoFrameTexture as Jh,VideoTexture as jh,WebGL3DRenderTarget as em,WebGLArrayRenderTarget as tm,WebGPUCoordinateSystem as nm,WireframeGeometry as im,WrapAroundEnding as rm,ZeroCurvatureEnding as am,ZeroSlopeEnding as om,ZeroStencilOp as sm}from"./build/three.core.mjs";function br(){let e=null,n=!1,t=null,i=null;function c(o,h){t(o,h),i=e.requestAnimationFrame(c)}return{start:function(){n!==!0&&t!==null&&(i=e.requestAnimationFrame(c),n=!0)},stop:function(){e.cancelAnimationFrame(i),n=!1},setAnimationLoop:function(o){t=o},setContext:function(o){e=o}}}function lo(e){let n=new WeakMap;function t(d,C){let M=d.array,D=d.usage,T=M.byteLength,g=e.createBuffer();e.bindBuffer(C,g),e.bufferData(C,M,D),d.onUploadCallback();let A;if(M instanceof Float32Array)A=e.FLOAT;else if(M instanceof Uint16Array)d.isFloat16BufferAttribute?A=e.HALF_FLOAT:A=e.UNSIGNED_SHORT;else if(M instanceof Int16Array)A=e.SHORT;else if(M instanceof Uint32Array)A=e.UNSIGNED_INT;else if(M instanceof Int32Array)A=e.INT;else if(M instanceof Int8Array)A=e.BYTE;else if(M instanceof Uint8Array)A=e.UNSIGNED_BYTE;else if(M instanceof Uint8ClampedArray)A=e.UNSIGNED_BYTE;else throw new Error("THREE.WebGLAttributes: Unsupported buffer data format: "+M);return{buffer:g,type:A,bytesPerElement:M.BYTES_PER_ELEMENT,version:d.version,size:T}}function i(d,C,M){let D=C.array,T=C.updateRanges;if(e.bindBuffer(M,d),T.length===0)e.bufferSubData(M,0,D);else{T.sort((A,N)=>A.start-N.start);let g=0;for(let A=1;A<T.length;A++){let N=T[g],L=T[A];L.start<=N.start+N.count+1?N.count=Math.max(N.count,L.start+L.count-N.start):(++g,T[g]=L)}T.length=g+1;for(let A=0,N=T.length;A<N;A++){let L=T[A];e.bufferSubData(M,L.start*D.BYTES_PER_ELEMENT,D,L.start,L.count)}C.clearUpdateRanges()}C.onUploadCallback()}function c(d){return d.isInterleavedBufferAttribute&&(d=d.data),n.get(d)}function o(d){d.isInterleavedBufferAttribute&&(d=d.data);let C=n.get(d);C&&(e.deleteBuffer(C.buffer),n.delete(d))}function h(d,C){if(d.isInterleavedBufferAttribute&&(d=d.data),d.isGLBufferAttribute){let D=n.get(d);(!D||D.version<d.version)&&n.set(d,{buffer:d.buffer,type:d.type,bytesPerElement:d.elementSize,version:d.version});return}let M=n.get(d);if(M===void 0)n.set(d,t(d,C));else if(M.version<d.version){if(M.size!==d.array.byteLength)throw new Error("THREE.WebGLAttributes: The size of the buffer attribute's array buffer does not match the original size. Resizing buffer attributes is not supported.");i(M.buffer,d,C),M.version=d.version}}return{get:c,remove:o,update:h}}var fo=`#ifdef USE_ALPHAHASH
	if ( diffuseColor.a < getAlphaHashThreshold( vPosition ) ) discard;
#endif`,uo=`#ifdef USE_ALPHAHASH
	const float ALPHA_HASH_SCALE = 0.05;
	float hash2D( vec2 value ) {
		return fract( 1.0e4 * sin( 17.0 * value.x + 0.1 * value.y ) * ( 0.1 + abs( sin( 13.0 * value.y + value.x ) ) ) );
	}
	float hash3D( vec3 value ) {
		return hash2D( vec2( hash2D( value.xy ), value.z ) );
	}
	float getAlphaHashThreshold( vec3 position ) {
		float maxDeriv = max(
			length( dFdx( position.xyz ) ),
			length( dFdy( position.xyz ) )
		);
		float pixScale = 1.0 / ( ALPHA_HASH_SCALE * maxDeriv );
		vec2 pixScales = vec2(
			exp2( floor( log2( pixScale ) ) ),
			exp2( ceil( log2( pixScale ) ) )
		);
		vec2 alpha = vec2(
			hash3D( floor( pixScales.x * position.xyz ) ),
			hash3D( floor( pixScales.y * position.xyz ) )
		);
		float lerpFactor = fract( log2( pixScale ) );
		float x = ( 1.0 - lerpFactor ) * alpha.x + lerpFactor * alpha.y;
		float a = min( lerpFactor, 1.0 - lerpFactor );
		vec3 cases = vec3(
			x * x / ( 2.0 * a * ( 1.0 - a ) ),
			( x - 0.5 * a ) / ( 1.0 - a ),
			1.0 - ( ( 1.0 - x ) * ( 1.0 - x ) / ( 2.0 * a * ( 1.0 - a ) ) )
		);
		float threshold = ( x < ( 1.0 - a ) )
			? ( ( x < a ) ? cases.x : cases.y )
			: cases.z;
		return clamp( threshold , 1.0e-6, 1.0 );
	}
#endif`,po=`#ifdef USE_ALPHAMAP
	diffuseColor.a *= texture2D( alphaMap, vAlphaMapUv ).g;
#endif`,ho=`#ifdef USE_ALPHAMAP
	uniform sampler2D alphaMap;
#endif`,mo=`#ifdef USE_ALPHATEST
	#ifdef ALPHA_TO_COVERAGE
	diffuseColor.a = smoothstep( alphaTest, alphaTest + fwidth( diffuseColor.a ), diffuseColor.a );
	if ( diffuseColor.a == 0.0 ) discard;
	#else
	if ( diffuseColor.a < alphaTest ) discard;
	#endif
#endif`,_o=`#ifdef USE_ALPHATEST
	uniform float alphaTest;
#endif`,vo=`#ifdef USE_AOMAP
	float ambientOcclusion = ( texture2D( aoMap, vAoMapUv ).r - 1.0 ) * aoMapIntensity + 1.0;
	reflectedLight.indirectDiffuse *= ambientOcclusion;
	#if defined( USE_CLEARCOAT )
		clearcoatSpecularIndirect *= ambientOcclusion;
	#endif
	#if defined( USE_SHEEN )
		sheenSpecularIndirect *= ambientOcclusion;
	#endif
	#if defined( USE_ENVMAP ) && defined( STANDARD )
		float dotNV = saturate( dot( geometryNormal, geometryViewDir ) );
		reflectedLight.indirectSpecular *= computeSpecularOcclusion( dotNV, ambientOcclusion, material.roughness );
	#endif
#endif`,go=`#ifdef USE_AOMAP
	uniform sampler2D aoMap;
	uniform float aoMapIntensity;
#endif`,So=`#ifdef USE_BATCHING
	#if ! defined( GL_ANGLE_multi_draw )
	#define gl_DrawID _gl_DrawID
	uniform int _gl_DrawID;
	#endif
	uniform highp sampler2D batchingTexture;
	uniform highp usampler2D batchingIdTexture;
	mat4 getBatchingMatrix( const in float i ) {
		int size = textureSize( batchingTexture, 0 ).x;
		int j = int( i ) * 4;
		int x = j % size;
		int y = j / size;
		vec4 v1 = texelFetch( batchingTexture, ivec2( x, y ), 0 );
		vec4 v2 = texelFetch( batchingTexture, ivec2( x + 1, y ), 0 );
		vec4 v3 = texelFetch( batchingTexture, ivec2( x + 2, y ), 0 );
		vec4 v4 = texelFetch( batchingTexture, ivec2( x + 3, y ), 0 );
		return mat4( v1, v2, v3, v4 );
	}
	float getIndirectIndex( const in int i ) {
		int size = textureSize( batchingIdTexture, 0 ).x;
		int x = i % size;
		int y = i / size;
		return float( texelFetch( batchingIdTexture, ivec2( x, y ), 0 ).r );
	}
#endif
#ifdef USE_BATCHING_COLOR
	uniform sampler2D batchingColorTexture;
	vec3 getBatchingColor( const in float i ) {
		int size = textureSize( batchingColorTexture, 0 ).x;
		int j = int( i );
		int x = j % size;
		int y = j / size;
		return texelFetch( batchingColorTexture, ivec2( x, y ), 0 ).rgb;
	}
#endif`,Eo=`#ifdef USE_BATCHING
	mat4 batchingMatrix = getBatchingMatrix( getIndirectIndex( gl_DrawID ) );
#endif`,Mo=`vec3 transformed = vec3( position );
#ifdef USE_ALPHAHASH
	vPosition = vec3( position );
#endif`,To=`vec3 objectNormal = vec3( normal );
#ifdef USE_TANGENT
	vec3 objectTangent = vec3( tangent.xyz );
#endif`,xo=`float G_BlinnPhong_Implicit( ) {
	return 0.25;
}
float D_BlinnPhong( const in float shininess, const in float dotNH ) {
	return RECIPROCAL_PI * ( shininess * 0.5 + 1.0 ) * pow( dotNH, shininess );
}
vec3 BRDF_BlinnPhong( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, const in vec3 specularColor, const in float shininess ) {
	vec3 halfDir = normalize( lightDir + viewDir );
	float dotNH = saturate( dot( normal, halfDir ) );
	float dotVH = saturate( dot( viewDir, halfDir ) );
	vec3 F = F_Schlick( specularColor, 1.0, dotVH );
	float G = G_BlinnPhong_Implicit( );
	float D = D_BlinnPhong( shininess, dotNH );
	return F * ( G * D );
} // validated`,Ao=`#ifdef USE_IRIDESCENCE
	const mat3 XYZ_TO_REC709 = mat3(
		 3.2404542, -0.9692660,  0.0556434,
		-1.5371385,  1.8760108, -0.2040259,
		-0.4985314,  0.0415560,  1.0572252
	);
	vec3 Fresnel0ToIor( vec3 fresnel0 ) {
		vec3 sqrtF0 = sqrt( fresnel0 );
		return ( vec3( 1.0 ) + sqrtF0 ) / ( vec3( 1.0 ) - sqrtF0 );
	}
	vec3 IorToFresnel0( vec3 transmittedIor, float incidentIor ) {
		return pow2( ( transmittedIor - vec3( incidentIor ) ) / ( transmittedIor + vec3( incidentIor ) ) );
	}
	float IorToFresnel0( float transmittedIor, float incidentIor ) {
		return pow2( ( transmittedIor - incidentIor ) / ( transmittedIor + incidentIor ));
	}
	vec3 evalSensitivity( float OPD, vec3 shift ) {
		float phase = 2.0 * PI * OPD * 1.0e-9;
		vec3 val = vec3( 5.4856e-13, 4.4201e-13, 5.2481e-13 );
		vec3 pos = vec3( 1.6810e+06, 1.7953e+06, 2.2084e+06 );
		vec3 var = vec3( 4.3278e+09, 9.3046e+09, 6.6121e+09 );
		vec3 xyz = val * sqrt( 2.0 * PI * var ) * cos( pos * phase + shift ) * exp( - pow2( phase ) * var );
		xyz.x += 9.7470e-14 * sqrt( 2.0 * PI * 4.5282e+09 ) * cos( 2.2399e+06 * phase + shift[ 0 ] ) * exp( - 4.5282e+09 * pow2( phase ) );
		xyz /= 1.0685e-7;
		vec3 rgb = XYZ_TO_REC709 * xyz;
		return rgb;
	}
	vec3 evalIridescence( float outsideIOR, float eta2, float cosTheta1, float thinFilmThickness, vec3 baseF0 ) {
		vec3 I;
		float iridescenceIOR = mix( outsideIOR, eta2, smoothstep( 0.0, 0.03, thinFilmThickness ) );
		float sinTheta2Sq = pow2( outsideIOR / iridescenceIOR ) * ( 1.0 - pow2( cosTheta1 ) );
		float cosTheta2Sq = 1.0 - sinTheta2Sq;
		if ( cosTheta2Sq < 0.0 ) {
			return vec3( 1.0 );
		}
		float cosTheta2 = sqrt( cosTheta2Sq );
		float R0 = IorToFresnel0( iridescenceIOR, outsideIOR );
		float R12 = F_Schlick( R0, 1.0, cosTheta1 );
		float T121 = 1.0 - R12;
		float phi12 = 0.0;
		if ( iridescenceIOR < outsideIOR ) phi12 = PI;
		float phi21 = PI - phi12;
		vec3 baseIOR = Fresnel0ToIor( clamp( baseF0, 0.0, 0.9999 ) );		vec3 R1 = IorToFresnel0( baseIOR, iridescenceIOR );
		vec3 R23 = F_Schlick( R1, 1.0, cosTheta2 );
		vec3 phi23 = vec3( 0.0 );
		if ( baseIOR[ 0 ] < iridescenceIOR ) phi23[ 0 ] = PI;
		if ( baseIOR[ 1 ] < iridescenceIOR ) phi23[ 1 ] = PI;
		if ( baseIOR[ 2 ] < iridescenceIOR ) phi23[ 2 ] = PI;
		float OPD = 2.0 * iridescenceIOR * thinFilmThickness * cosTheta2;
		vec3 phi = vec3( phi21 ) + phi23;
		vec3 R123 = clamp( R12 * R23, 1e-5, 0.9999 );
		vec3 r123 = sqrt( R123 );
		vec3 Rs = pow2( T121 ) * R23 / ( vec3( 1.0 ) - R123 );
		vec3 C0 = R12 + Rs;
		I = C0;
		vec3 Cm = Rs - T121;
		for ( int m = 1; m <= 2; ++ m ) {
			Cm *= r123;
			vec3 Sm = 2.0 * evalSensitivity( float( m ) * OPD, float( m ) * phi );
			I += Cm * Sm;
		}
		return max( I, vec3( 0.0 ) );
	}
#endif`,Ro=`#ifdef USE_BUMPMAP
	uniform sampler2D bumpMap;
	uniform float bumpScale;
	vec2 dHdxy_fwd() {
		vec2 dSTdx = dFdx( vBumpMapUv );
		vec2 dSTdy = dFdy( vBumpMapUv );
		float Hll = bumpScale * texture2D( bumpMap, vBumpMapUv ).x;
		float dBx = bumpScale * texture2D( bumpMap, vBumpMapUv + dSTdx ).x - Hll;
		float dBy = bumpScale * texture2D( bumpMap, vBumpMapUv + dSTdy ).x - Hll;
		return vec2( dBx, dBy );
	}
	vec3 perturbNormalArb( vec3 surf_pos, vec3 surf_norm, vec2 dHdxy, float faceDirection ) {
		vec3 vSigmaX = normalize( dFdx( surf_pos.xyz ) );
		vec3 vSigmaY = normalize( dFdy( surf_pos.xyz ) );
		vec3 vN = surf_norm;
		vec3 R1 = cross( vSigmaY, vN );
		vec3 R2 = cross( vN, vSigmaX );
		float fDet = dot( vSigmaX, R1 ) * faceDirection;
		vec3 vGrad = sign( fDet ) * ( dHdxy.x * R1 + dHdxy.y * R2 );
		return normalize( abs( fDet ) * surf_norm - vGrad );
	}
#endif`,Co=`#if NUM_CLIPPING_PLANES > 0
	vec4 plane;
	#ifdef ALPHA_TO_COVERAGE
		float distanceToPlane, distanceGradient;
		float clipOpacity = 1.0;
		#pragma unroll_loop_start
		for ( int i = 0; i < UNION_CLIPPING_PLANES; i ++ ) {
			plane = clippingPlanes[ i ];
			distanceToPlane = - dot( vClipPosition, plane.xyz ) + plane.w;
			distanceGradient = fwidth( distanceToPlane ) / 2.0;
			clipOpacity *= smoothstep( - distanceGradient, distanceGradient, distanceToPlane );
			if ( clipOpacity == 0.0 ) discard;
		}
		#pragma unroll_loop_end
		#if UNION_CLIPPING_PLANES < NUM_CLIPPING_PLANES
			float unionClipOpacity = 1.0;
			#pragma unroll_loop_start
			for ( int i = UNION_CLIPPING_PLANES; i < NUM_CLIPPING_PLANES; i ++ ) {
				plane = clippingPlanes[ i ];
				distanceToPlane = - dot( vClipPosition, plane.xyz ) + plane.w;
				distanceGradient = fwidth( distanceToPlane ) / 2.0;
				unionClipOpacity *= 1.0 - smoothstep( - distanceGradient, distanceGradient, distanceToPlane );
			}
			#pragma unroll_loop_end
			clipOpacity *= 1.0 - unionClipOpacity;
		#endif
		diffuseColor.a *= clipOpacity;
		if ( diffuseColor.a == 0.0 ) discard;
	#else
		#pragma unroll_loop_start
		for ( int i = 0; i < UNION_CLIPPING_PLANES; i ++ ) {
			plane = clippingPlanes[ i ];
			if ( dot( vClipPosition, plane.xyz ) > plane.w ) discard;
		}
		#pragma unroll_loop_end
		#if UNION_CLIPPING_PLANES < NUM_CLIPPING_PLANES
			bool clipped = true;
			#pragma unroll_loop_start
			for ( int i = UNION_CLIPPING_PLANES; i < NUM_CLIPPING_PLANES; i ++ ) {
				plane = clippingPlanes[ i ];
				clipped = ( dot( vClipPosition, plane.xyz ) > plane.w ) && clipped;
			}
			#pragma unroll_loop_end
			if ( clipped ) discard;
		#endif
	#endif
#endif`,bo=`#if NUM_CLIPPING_PLANES > 0
	varying vec3 vClipPosition;
	uniform vec4 clippingPlanes[ NUM_CLIPPING_PLANES ];
#endif`,Po=`#if NUM_CLIPPING_PLANES > 0
	varying vec3 vClipPosition;
#endif`,Lo=`#if NUM_CLIPPING_PLANES > 0
	vClipPosition = - mvPosition.xyz;
#endif`,Uo=`#if defined( USE_COLOR_ALPHA )
	diffuseColor *= vColor;
#elif defined( USE_COLOR )
	diffuseColor.rgb *= vColor;
#endif`,Do=`#if defined( USE_COLOR_ALPHA )
	varying vec4 vColor;
#elif defined( USE_COLOR )
	varying vec3 vColor;
#endif`,wo=`#if defined( USE_COLOR_ALPHA )
	varying vec4 vColor;
#elif defined( USE_COLOR ) || defined( USE_INSTANCING_COLOR ) || defined( USE_BATCHING_COLOR )
	varying vec3 vColor;
#endif`,Io=`#if defined( USE_COLOR_ALPHA )
	vColor = vec4( 1.0 );
#elif defined( USE_COLOR ) || defined( USE_INSTANCING_COLOR ) || defined( USE_BATCHING_COLOR )
	vColor = vec3( 1.0 );
#endif
#ifdef USE_COLOR
	vColor *= color;
#endif
#ifdef USE_INSTANCING_COLOR
	vColor.xyz *= instanceColor.xyz;
#endif
#ifdef USE_BATCHING_COLOR
	vec3 batchingColor = getBatchingColor( getIndirectIndex( gl_DrawID ) );
	vColor.xyz *= batchingColor.xyz;
#endif`,yo=`#define PI 3.141592653589793
#define PI2 6.283185307179586
#define PI_HALF 1.5707963267948966
#define RECIPROCAL_PI 0.3183098861837907
#define RECIPROCAL_PI2 0.15915494309189535
#define EPSILON 1e-6
#ifndef saturate
#define saturate( a ) clamp( a, 0.0, 1.0 )
#endif
#define whiteComplement( a ) ( 1.0 - saturate( a ) )
float pow2( const in float x ) { return x*x; }
vec3 pow2( const in vec3 x ) { return x*x; }
float pow3( const in float x ) { return x*x*x; }
float pow4( const in float x ) { float x2 = x*x; return x2*x2; }
float max3( const in vec3 v ) { return max( max( v.x, v.y ), v.z ); }
float average( const in vec3 v ) { return dot( v, vec3( 0.3333333 ) ); }
highp float rand( const in vec2 uv ) {
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract( sin( sn ) * c );
}
#ifdef HIGH_PRECISION
	float precisionSafeLength( vec3 v ) { return length( v ); }
#else
	float precisionSafeLength( vec3 v ) {
		float maxComponent = max3( abs( v ) );
		return length( v / maxComponent ) * maxComponent;
	}
#endif
struct IncidentLight {
	vec3 color;
	vec3 direction;
	bool visible;
};
struct ReflectedLight {
	vec3 directDiffuse;
	vec3 directSpecular;
	vec3 indirectDiffuse;
	vec3 indirectSpecular;
};
#ifdef USE_ALPHAHASH
	varying vec3 vPosition;
#endif
vec3 transformDirection( in vec3 dir, in mat4 matrix ) {
	return normalize( ( matrix * vec4( dir, 0.0 ) ).xyz );
}
vec3 inverseTransformDirection( in vec3 dir, in mat4 matrix ) {
	return normalize( ( vec4( dir, 0.0 ) * matrix ).xyz );
}
mat3 transposeMat3( const in mat3 m ) {
	mat3 tmp;
	tmp[ 0 ] = vec3( m[ 0 ].x, m[ 1 ].x, m[ 2 ].x );
	tmp[ 1 ] = vec3( m[ 0 ].y, m[ 1 ].y, m[ 2 ].y );
	tmp[ 2 ] = vec3( m[ 0 ].z, m[ 1 ].z, m[ 2 ].z );
	return tmp;
}
bool isPerspectiveMatrix( mat4 m ) {
	return m[ 2 ][ 3 ] == - 1.0;
}
vec2 equirectUv( in vec3 dir ) {
	float u = atan( dir.z, dir.x ) * RECIPROCAL_PI2 + 0.5;
	float v = asin( clamp( dir.y, - 1.0, 1.0 ) ) * RECIPROCAL_PI + 0.5;
	return vec2( u, v );
}
vec3 BRDF_Lambert( const in vec3 diffuseColor ) {
	return RECIPROCAL_PI * diffuseColor;
}
vec3 F_Schlick( const in vec3 f0, const in float f90, const in float dotVH ) {
	float fresnel = exp2( ( - 5.55473 * dotVH - 6.98316 ) * dotVH );
	return f0 * ( 1.0 - fresnel ) + ( f90 * fresnel );
}
float F_Schlick( const in float f0, const in float f90, const in float dotVH ) {
	float fresnel = exp2( ( - 5.55473 * dotVH - 6.98316 ) * dotVH );
	return f0 * ( 1.0 - fresnel ) + ( f90 * fresnel );
} // validated`,No=`#ifdef ENVMAP_TYPE_CUBE_UV
	#define cubeUV_minMipLevel 4.0
	#define cubeUV_minTileSize 16.0
	float getFace( vec3 direction ) {
		vec3 absDirection = abs( direction );
		float face = - 1.0;
		if ( absDirection.x > absDirection.z ) {
			if ( absDirection.x > absDirection.y )
				face = direction.x > 0.0 ? 0.0 : 3.0;
			else
				face = direction.y > 0.0 ? 1.0 : 4.0;
		} else {
			if ( absDirection.z > absDirection.y )
				face = direction.z > 0.0 ? 2.0 : 5.0;
			else
				face = direction.y > 0.0 ? 1.0 : 4.0;
		}
		return face;
	}
	vec2 getUV( vec3 direction, float face ) {
		vec2 uv;
		if ( face == 0.0 ) {
			uv = vec2( direction.z, direction.y ) / abs( direction.x );
		} else if ( face == 1.0 ) {
			uv = vec2( - direction.x, - direction.z ) / abs( direction.y );
		} else if ( face == 2.0 ) {
			uv = vec2( - direction.x, direction.y ) / abs( direction.z );
		} else if ( face == 3.0 ) {
			uv = vec2( - direction.z, direction.y ) / abs( direction.x );
		} else if ( face == 4.0 ) {
			uv = vec2( - direction.x, direction.z ) / abs( direction.y );
		} else {
			uv = vec2( direction.x, direction.y ) / abs( direction.z );
		}
		return 0.5 * ( uv + 1.0 );
	}
	vec3 bilinearCubeUV( sampler2D envMap, vec3 direction, float mipInt ) {
		float face = getFace( direction );
		float filterInt = max( cubeUV_minMipLevel - mipInt, 0.0 );
		mipInt = max( mipInt, cubeUV_minMipLevel );
		float faceSize = exp2( mipInt );
		highp vec2 uv = getUV( direction, face ) * ( faceSize - 2.0 ) + 1.0;
		if ( face > 2.0 ) {
			uv.y += faceSize;
			face -= 3.0;
		}
		uv.x += face * faceSize;
		uv.x += filterInt * 3.0 * cubeUV_minTileSize;
		uv.y += 4.0 * ( exp2( CUBEUV_MAX_MIP ) - faceSize );
		uv.x *= CUBEUV_TEXEL_WIDTH;
		uv.y *= CUBEUV_TEXEL_HEIGHT;
		#ifdef texture2DGradEXT
			return texture2DGradEXT( envMap, uv, vec2( 0.0 ), vec2( 0.0 ) ).rgb;
		#else
			return texture2D( envMap, uv ).rgb;
		#endif
	}
	#define cubeUV_r0 1.0
	#define cubeUV_m0 - 2.0
	#define cubeUV_r1 0.8
	#define cubeUV_m1 - 1.0
	#define cubeUV_r4 0.4
	#define cubeUV_m4 2.0
	#define cubeUV_r5 0.305
	#define cubeUV_m5 3.0
	#define cubeUV_r6 0.21
	#define cubeUV_m6 4.0
	float roughnessToMip( float roughness ) {
		float mip = 0.0;
		if ( roughness >= cubeUV_r1 ) {
			mip = ( cubeUV_r0 - roughness ) * ( cubeUV_m1 - cubeUV_m0 ) / ( cubeUV_r0 - cubeUV_r1 ) + cubeUV_m0;
		} else if ( roughness >= cubeUV_r4 ) {
			mip = ( cubeUV_r1 - roughness ) * ( cubeUV_m4 - cubeUV_m1 ) / ( cubeUV_r1 - cubeUV_r4 ) + cubeUV_m1;
		} else if ( roughness >= cubeUV_r5 ) {
			mip = ( cubeUV_r4 - roughness ) * ( cubeUV_m5 - cubeUV_m4 ) / ( cubeUV_r4 - cubeUV_r5 ) + cubeUV_m4;
		} else if ( roughness >= cubeUV_r6 ) {
			mip = ( cubeUV_r5 - roughness ) * ( cubeUV_m6 - cubeUV_m5 ) / ( cubeUV_r5 - cubeUV_r6 ) + cubeUV_m5;
		} else {
			mip = - 2.0 * log2( 1.16 * roughness );		}
		return mip;
	}
	vec4 textureCubeUV( sampler2D envMap, vec3 sampleDir, float roughness ) {
		float mip = clamp( roughnessToMip( roughness ), cubeUV_m0, CUBEUV_MAX_MIP );
		float mipF = fract( mip );
		float mipInt = floor( mip );
		vec3 color0 = bilinearCubeUV( envMap, sampleDir, mipInt );
		if ( mipF == 0.0 ) {
			return vec4( color0, 1.0 );
		} else {
			vec3 color1 = bilinearCubeUV( envMap, sampleDir, mipInt + 1.0 );
			return vec4( mix( color0, color1, mipF ), 1.0 );
		}
	}
#endif`,Oo=`vec3 transformedNormal = objectNormal;
#ifdef USE_TANGENT
	vec3 transformedTangent = objectTangent;
#endif
#ifdef USE_BATCHING
	mat3 bm = mat3( batchingMatrix );
	transformedNormal /= vec3( dot( bm[ 0 ], bm[ 0 ] ), dot( bm[ 1 ], bm[ 1 ] ), dot( bm[ 2 ], bm[ 2 ] ) );
	transformedNormal = bm * transformedNormal;
	#ifdef USE_TANGENT
		transformedTangent = bm * transformedTangent;
	#endif
#endif
#ifdef USE_INSTANCING
	mat3 im = mat3( instanceMatrix );
	transformedNormal /= vec3( dot( im[ 0 ], im[ 0 ] ), dot( im[ 1 ], im[ 1 ] ), dot( im[ 2 ], im[ 2 ] ) );
	transformedNormal = im * transformedNormal;
	#ifdef USE_TANGENT
		transformedTangent = im * transformedTangent;
	#endif
#endif
transformedNormal = normalMatrix * transformedNormal;
#ifdef FLIP_SIDED
	transformedNormal = - transformedNormal;
#endif
#ifdef USE_TANGENT
	transformedTangent = ( modelViewMatrix * vec4( transformedTangent, 0.0 ) ).xyz;
	#ifdef FLIP_SIDED
		transformedTangent = - transformedTangent;
	#endif
#endif`,Fo=`#ifdef USE_DISPLACEMENTMAP
	uniform sampler2D displacementMap;
	uniform float displacementScale;
	uniform float displacementBias;
#endif`,Bo=`#ifdef USE_DISPLACEMENTMAP
	transformed += normalize( objectNormal ) * ( texture2D( displacementMap, vDisplacementMapUv ).x * displacementScale + displacementBias );
#endif`,Go=`#ifdef USE_EMISSIVEMAP
	vec4 emissiveColor = texture2D( emissiveMap, vEmissiveMapUv );
	#ifdef DECODE_VIDEO_TEXTURE_EMISSIVE
		emissiveColor = sRGBTransferEOTF( emissiveColor );
	#endif
	totalEmissiveRadiance *= emissiveColor.rgb;
#endif`,Ho=`#ifdef USE_EMISSIVEMAP
	uniform sampler2D emissiveMap;
#endif`,Vo="gl_FragColor = linearToOutputTexel( gl_FragColor );",ko=`vec4 LinearTransferOETF( in vec4 value ) {
	return value;
}
vec4 sRGBTransferEOTF( in vec4 value ) {
	return vec4( mix( pow( value.rgb * 0.9478672986 + vec3( 0.0521327014 ), vec3( 2.4 ) ), value.rgb * 0.0773993808, vec3( lessThanEqual( value.rgb, vec3( 0.04045 ) ) ) ), value.a );
}
vec4 sRGBTransferOETF( in vec4 value ) {
	return vec4( mix( pow( value.rgb, vec3( 0.41666 ) ) * 1.055 - vec3( 0.055 ), value.rgb * 12.92, vec3( lessThanEqual( value.rgb, vec3( 0.0031308 ) ) ) ), value.a );
}`,zo=`#ifdef USE_ENVMAP
	#ifdef ENV_WORLDPOS
		vec3 cameraToFrag;
		if ( isOrthographic ) {
			cameraToFrag = normalize( vec3( - viewMatrix[ 0 ][ 2 ], - viewMatrix[ 1 ][ 2 ], - viewMatrix[ 2 ][ 2 ] ) );
		} else {
			cameraToFrag = normalize( vWorldPosition - cameraPosition );
		}
		vec3 worldNormal = inverseTransformDirection( normal, viewMatrix );
		#ifdef ENVMAP_MODE_REFLECTION
			vec3 reflectVec = reflect( cameraToFrag, worldNormal );
		#else
			vec3 reflectVec = refract( cameraToFrag, worldNormal, refractionRatio );
		#endif
	#else
		vec3 reflectVec = vReflect;
	#endif
	#ifdef ENVMAP_TYPE_CUBE
		vec4 envColor = textureCube( envMap, envMapRotation * vec3( flipEnvMap * reflectVec.x, reflectVec.yz ) );
	#else
		vec4 envColor = vec4( 0.0 );
	#endif
	#ifdef ENVMAP_BLENDING_MULTIPLY
		outgoingLight = mix( outgoingLight, outgoingLight * envColor.xyz, specularStrength * reflectivity );
	#elif defined( ENVMAP_BLENDING_MIX )
		outgoingLight = mix( outgoingLight, envColor.xyz, specularStrength * reflectivity );
	#elif defined( ENVMAP_BLENDING_ADD )
		outgoingLight += envColor.xyz * specularStrength * reflectivity;
	#endif
#endif`,Wo=`#ifdef USE_ENVMAP
	uniform float envMapIntensity;
	uniform float flipEnvMap;
	uniform mat3 envMapRotation;
	#ifdef ENVMAP_TYPE_CUBE
		uniform samplerCube envMap;
	#else
		uniform sampler2D envMap;
	#endif

#endif`,Xo=`#ifdef USE_ENVMAP
	uniform float reflectivity;
	#if defined( USE_BUMPMAP ) || defined( USE_NORMALMAP ) || defined( PHONG ) || defined( LAMBERT )
		#define ENV_WORLDPOS
	#endif
	#ifdef ENV_WORLDPOS
		varying vec3 vWorldPosition;
		uniform float refractionRatio;
	#else
		varying vec3 vReflect;
	#endif
#endif`,Ko=`#ifdef USE_ENVMAP
	#if defined( USE_BUMPMAP ) || defined( USE_NORMALMAP ) || defined( PHONG ) || defined( LAMBERT )
		#define ENV_WORLDPOS
	#endif
	#ifdef ENV_WORLDPOS

		varying vec3 vWorldPosition;
	#else
		varying vec3 vReflect;
		uniform float refractionRatio;
	#endif
#endif`,Yo=`#ifdef USE_ENVMAP
	#ifdef ENV_WORLDPOS
		vWorldPosition = worldPosition.xyz;
	#else
		vec3 cameraToVertex;
		if ( isOrthographic ) {
			cameraToVertex = normalize( vec3( - viewMatrix[ 0 ][ 2 ], - viewMatrix[ 1 ][ 2 ], - viewMatrix[ 2 ][ 2 ] ) );
		} else {
			cameraToVertex = normalize( worldPosition.xyz - cameraPosition );
		}
		vec3 worldNormal = inverseTransformDirection( transformedNormal, viewMatrix );
		#ifdef ENVMAP_MODE_REFLECTION
			vReflect = reflect( cameraToVertex, worldNormal );
		#else
			vReflect = refract( cameraToVertex, worldNormal, refractionRatio );
		#endif
	#endif
#endif`,qo=`#ifdef USE_FOG
	vFogDepth = - mvPosition.z;
#endif`,$o=`#ifdef USE_FOG
	varying float vFogDepth;
#endif`,Zo=`#ifdef USE_FOG
	#ifdef FOG_EXP2
		float fogFactor = 1.0 - exp( - fogDensity * fogDensity * vFogDepth * vFogDepth );
	#else
		float fogFactor = smoothstep( fogNear, fogFar, vFogDepth );
	#endif
	gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor );
#endif`,Qo=`#ifdef USE_FOG
	uniform vec3 fogColor;
	varying float vFogDepth;
	#ifdef FOG_EXP2
		uniform float fogDensity;
	#else
		uniform float fogNear;
		uniform float fogFar;
	#endif
#endif`,Jo=`#ifdef USE_GRADIENTMAP
	uniform sampler2D gradientMap;
#endif
vec3 getGradientIrradiance( vec3 normal, vec3 lightDirection ) {
	float dotNL = dot( normal, lightDirection );
	vec2 coord = vec2( dotNL * 0.5 + 0.5, 0.0 );
	#ifdef USE_GRADIENTMAP
		return vec3( texture2D( gradientMap, coord ).r );
	#else
		vec2 fw = fwidth( coord ) * 0.5;
		return mix( vec3( 0.7 ), vec3( 1.0 ), smoothstep( 0.7 - fw.x, 0.7 + fw.x, coord.x ) );
	#endif
}`,jo=`#ifdef USE_LIGHTMAP
	uniform sampler2D lightMap;
	uniform float lightMapIntensity;
#endif`,es=`LambertMaterial material;
material.diffuseColor = diffuseColor.rgb;
material.specularStrength = specularStrength;`,ts=`varying vec3 vViewPosition;
struct LambertMaterial {
	vec3 diffuseColor;
	float specularStrength;
};
void RE_Direct_Lambert( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in LambertMaterial material, inout ReflectedLight reflectedLight ) {
	float dotNL = saturate( dot( geometryNormal, directLight.direction ) );
	vec3 irradiance = dotNL * directLight.color;
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectDiffuse_Lambert( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in LambertMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
#define RE_Direct				RE_Direct_Lambert
#define RE_IndirectDiffuse		RE_IndirectDiffuse_Lambert`,ns=`uniform bool receiveShadow;
uniform vec3 ambientLightColor;
#if defined( USE_LIGHT_PROBES )
	uniform vec3 lightProbe[ 9 ];
#endif
vec3 shGetIrradianceAt( in vec3 normal, in vec3 shCoefficients[ 9 ] ) {
	float x = normal.x, y = normal.y, z = normal.z;
	vec3 result = shCoefficients[ 0 ] * 0.886227;
	result += shCoefficients[ 1 ] * 2.0 * 0.511664 * y;
	result += shCoefficients[ 2 ] * 2.0 * 0.511664 * z;
	result += shCoefficients[ 3 ] * 2.0 * 0.511664 * x;
	result += shCoefficients[ 4 ] * 2.0 * 0.429043 * x * y;
	result += shCoefficients[ 5 ] * 2.0 * 0.429043 * y * z;
	result += shCoefficients[ 6 ] * ( 0.743125 * z * z - 0.247708 );
	result += shCoefficients[ 7 ] * 2.0 * 0.429043 * x * z;
	result += shCoefficients[ 8 ] * 0.429043 * ( x * x - y * y );
	return result;
}
vec3 getLightProbeIrradiance( const in vec3 lightProbe[ 9 ], const in vec3 normal ) {
	vec3 worldNormal = inverseTransformDirection( normal, viewMatrix );
	vec3 irradiance = shGetIrradianceAt( worldNormal, lightProbe );
	return irradiance;
}
vec3 getAmbientLightIrradiance( const in vec3 ambientLightColor ) {
	vec3 irradiance = ambientLightColor;
	return irradiance;
}
float getDistanceAttenuation( const in float lightDistance, const in float cutoffDistance, const in float decayExponent ) {
	float distanceFalloff = 1.0 / max( pow( lightDistance, decayExponent ), 0.01 );
	if ( cutoffDistance > 0.0 ) {
		distanceFalloff *= pow2( saturate( 1.0 - pow4( lightDistance / cutoffDistance ) ) );
	}
	return distanceFalloff;
}
float getSpotAttenuation( const in float coneCosine, const in float penumbraCosine, const in float angleCosine ) {
	return smoothstep( coneCosine, penumbraCosine, angleCosine );
}
#if NUM_DIR_LIGHTS > 0
	struct DirectionalLight {
		vec3 direction;
		vec3 color;
	};
	uniform DirectionalLight directionalLights[ NUM_DIR_LIGHTS ];
	void getDirectionalLightInfo( const in DirectionalLight directionalLight, out IncidentLight light ) {
		light.color = directionalLight.color;
		light.direction = directionalLight.direction;
		light.visible = true;
	}
#endif
#if NUM_POINT_LIGHTS > 0
	struct PointLight {
		vec3 position;
		vec3 color;
		float distance;
		float decay;
	};
	uniform PointLight pointLights[ NUM_POINT_LIGHTS ];
	void getPointLightInfo( const in PointLight pointLight, const in vec3 geometryPosition, out IncidentLight light ) {
		vec3 lVector = pointLight.position - geometryPosition;
		light.direction = normalize( lVector );
		float lightDistance = length( lVector );
		light.color = pointLight.color;
		light.color *= getDistanceAttenuation( lightDistance, pointLight.distance, pointLight.decay );
		light.visible = ( light.color != vec3( 0.0 ) );
	}
#endif
#if NUM_SPOT_LIGHTS > 0
	struct SpotLight {
		vec3 position;
		vec3 direction;
		vec3 color;
		float distance;
		float decay;
		float coneCos;
		float penumbraCos;
	};
	uniform SpotLight spotLights[ NUM_SPOT_LIGHTS ];
	void getSpotLightInfo( const in SpotLight spotLight, const in vec3 geometryPosition, out IncidentLight light ) {
		vec3 lVector = spotLight.position - geometryPosition;
		light.direction = normalize( lVector );
		float angleCos = dot( light.direction, spotLight.direction );
		float spotAttenuation = getSpotAttenuation( spotLight.coneCos, spotLight.penumbraCos, angleCos );
		if ( spotAttenuation > 0.0 ) {
			float lightDistance = length( lVector );
			light.color = spotLight.color * spotAttenuation;
			light.color *= getDistanceAttenuation( lightDistance, spotLight.distance, spotLight.decay );
			light.visible = ( light.color != vec3( 0.0 ) );
		} else {
			light.color = vec3( 0.0 );
			light.visible = false;
		}
	}
#endif
#if NUM_RECT_AREA_LIGHTS > 0
	struct RectAreaLight {
		vec3 color;
		vec3 position;
		vec3 halfWidth;
		vec3 halfHeight;
	};
	uniform sampler2D ltc_1;	uniform sampler2D ltc_2;
	uniform RectAreaLight rectAreaLights[ NUM_RECT_AREA_LIGHTS ];
#endif
#if NUM_HEMI_LIGHTS > 0
	struct HemisphereLight {
		vec3 direction;
		vec3 skyColor;
		vec3 groundColor;
	};
	uniform HemisphereLight hemisphereLights[ NUM_HEMI_LIGHTS ];
	vec3 getHemisphereLightIrradiance( const in HemisphereLight hemiLight, const in vec3 normal ) {
		float dotNL = dot( normal, hemiLight.direction );
		float hemiDiffuseWeight = 0.5 * dotNL + 0.5;
		vec3 irradiance = mix( hemiLight.groundColor, hemiLight.skyColor, hemiDiffuseWeight );
		return irradiance;
	}
#endif`,is=`#ifdef USE_ENVMAP
	vec3 getIBLIrradiance( const in vec3 normal ) {
		#ifdef ENVMAP_TYPE_CUBE_UV
			vec3 worldNormal = inverseTransformDirection( normal, viewMatrix );
			vec4 envMapColor = textureCubeUV( envMap, envMapRotation * worldNormal, 1.0 );
			return PI * envMapColor.rgb * envMapIntensity;
		#else
			return vec3( 0.0 );
		#endif
	}
	vec3 getIBLRadiance( const in vec3 viewDir, const in vec3 normal, const in float roughness ) {
		#ifdef ENVMAP_TYPE_CUBE_UV
			vec3 reflectVec = reflect( - viewDir, normal );
			reflectVec = normalize( mix( reflectVec, normal, roughness * roughness) );
			reflectVec = inverseTransformDirection( reflectVec, viewMatrix );
			vec4 envMapColor = textureCubeUV( envMap, envMapRotation * reflectVec, roughness );
			return envMapColor.rgb * envMapIntensity;
		#else
			return vec3( 0.0 );
		#endif
	}
	#ifdef USE_ANISOTROPY
		vec3 getIBLAnisotropyRadiance( const in vec3 viewDir, const in vec3 normal, const in float roughness, const in vec3 bitangent, const in float anisotropy ) {
			#ifdef ENVMAP_TYPE_CUBE_UV
				vec3 bentNormal = cross( bitangent, viewDir );
				bentNormal = normalize( cross( bentNormal, bitangent ) );
				bentNormal = normalize( mix( bentNormal, normal, pow2( pow2( 1.0 - anisotropy * ( 1.0 - roughness ) ) ) ) );
				return getIBLRadiance( viewDir, bentNormal, roughness );
			#else
				return vec3( 0.0 );
			#endif
		}
	#endif
#endif`,rs=`ToonMaterial material;
material.diffuseColor = diffuseColor.rgb;`,as=`varying vec3 vViewPosition;
struct ToonMaterial {
	vec3 diffuseColor;
};
void RE_Direct_Toon( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in ToonMaterial material, inout ReflectedLight reflectedLight ) {
	vec3 irradiance = getGradientIrradiance( geometryNormal, directLight.direction ) * directLight.color;
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectDiffuse_Toon( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in ToonMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
#define RE_Direct				RE_Direct_Toon
#define RE_IndirectDiffuse		RE_IndirectDiffuse_Toon`,os=`BlinnPhongMaterial material;
material.diffuseColor = diffuseColor.rgb;
material.specularColor = specular;
material.specularShininess = shininess;
material.specularStrength = specularStrength;`,ss=`varying vec3 vViewPosition;
struct BlinnPhongMaterial {
	vec3 diffuseColor;
	vec3 specularColor;
	float specularShininess;
	float specularStrength;
};
void RE_Direct_BlinnPhong( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in BlinnPhongMaterial material, inout ReflectedLight reflectedLight ) {
	float dotNL = saturate( dot( geometryNormal, directLight.direction ) );
	vec3 irradiance = dotNL * directLight.color;
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
	reflectedLight.directSpecular += irradiance * BRDF_BlinnPhong( directLight.direction, geometryViewDir, geometryNormal, material.specularColor, material.specularShininess ) * material.specularStrength;
}
void RE_IndirectDiffuse_BlinnPhong( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in BlinnPhongMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
#define RE_Direct				RE_Direct_BlinnPhong
#define RE_IndirectDiffuse		RE_IndirectDiffuse_BlinnPhong`,cs=`PhysicalMaterial material;
material.diffuseColor = diffuseColor.rgb * ( 1.0 - metalnessFactor );
vec3 dxy = max( abs( dFdx( nonPerturbedNormal ) ), abs( dFdy( nonPerturbedNormal ) ) );
float geometryRoughness = max( max( dxy.x, dxy.y ), dxy.z );
material.roughness = max( roughnessFactor, 0.0525 );material.roughness += geometryRoughness;
material.roughness = min( material.roughness, 1.0 );
#ifdef IOR
	material.ior = ior;
	#ifdef USE_SPECULAR
		float specularIntensityFactor = specularIntensity;
		vec3 specularColorFactor = specularColor;
		#ifdef USE_SPECULAR_COLORMAP
			specularColorFactor *= texture2D( specularColorMap, vSpecularColorMapUv ).rgb;
		#endif
		#ifdef USE_SPECULAR_INTENSITYMAP
			specularIntensityFactor *= texture2D( specularIntensityMap, vSpecularIntensityMapUv ).a;
		#endif
		material.specularF90 = mix( specularIntensityFactor, 1.0, metalnessFactor );
	#else
		float specularIntensityFactor = 1.0;
		vec3 specularColorFactor = vec3( 1.0 );
		material.specularF90 = 1.0;
	#endif
	material.specularColor = mix( min( pow2( ( material.ior - 1.0 ) / ( material.ior + 1.0 ) ) * specularColorFactor, vec3( 1.0 ) ) * specularIntensityFactor, diffuseColor.rgb, metalnessFactor );
#else
	material.specularColor = mix( vec3( 0.04 ), diffuseColor.rgb, metalnessFactor );
	material.specularF90 = 1.0;
#endif
#ifdef USE_CLEARCOAT
	material.clearcoat = clearcoat;
	material.clearcoatRoughness = clearcoatRoughness;
	material.clearcoatF0 = vec3( 0.04 );
	material.clearcoatF90 = 1.0;
	#ifdef USE_CLEARCOATMAP
		material.clearcoat *= texture2D( clearcoatMap, vClearcoatMapUv ).x;
	#endif
	#ifdef USE_CLEARCOAT_ROUGHNESSMAP
		material.clearcoatRoughness *= texture2D( clearcoatRoughnessMap, vClearcoatRoughnessMapUv ).y;
	#endif
	material.clearcoat = saturate( material.clearcoat );	material.clearcoatRoughness = max( material.clearcoatRoughness, 0.0525 );
	material.clearcoatRoughness += geometryRoughness;
	material.clearcoatRoughness = min( material.clearcoatRoughness, 1.0 );
#endif
#ifdef USE_DISPERSION
	material.dispersion = dispersion;
#endif
#ifdef USE_IRIDESCENCE
	material.iridescence = iridescence;
	material.iridescenceIOR = iridescenceIOR;
	#ifdef USE_IRIDESCENCEMAP
		material.iridescence *= texture2D( iridescenceMap, vIridescenceMapUv ).r;
	#endif
	#ifdef USE_IRIDESCENCE_THICKNESSMAP
		material.iridescenceThickness = (iridescenceThicknessMaximum - iridescenceThicknessMinimum) * texture2D( iridescenceThicknessMap, vIridescenceThicknessMapUv ).g + iridescenceThicknessMinimum;
	#else
		material.iridescenceThickness = iridescenceThicknessMaximum;
	#endif
#endif
#ifdef USE_SHEEN
	material.sheenColor = sheenColor;
	#ifdef USE_SHEEN_COLORMAP
		material.sheenColor *= texture2D( sheenColorMap, vSheenColorMapUv ).rgb;
	#endif
	material.sheenRoughness = clamp( sheenRoughness, 0.07, 1.0 );
	#ifdef USE_SHEEN_ROUGHNESSMAP
		material.sheenRoughness *= texture2D( sheenRoughnessMap, vSheenRoughnessMapUv ).a;
	#endif
#endif
#ifdef USE_ANISOTROPY
	#ifdef USE_ANISOTROPYMAP
		mat2 anisotropyMat = mat2( anisotropyVector.x, anisotropyVector.y, - anisotropyVector.y, anisotropyVector.x );
		vec3 anisotropyPolar = texture2D( anisotropyMap, vAnisotropyMapUv ).rgb;
		vec2 anisotropyV = anisotropyMat * normalize( 2.0 * anisotropyPolar.rg - vec2( 1.0 ) ) * anisotropyPolar.b;
	#else
		vec2 anisotropyV = anisotropyVector;
	#endif
	material.anisotropy = length( anisotropyV );
	if( material.anisotropy == 0.0 ) {
		anisotropyV = vec2( 1.0, 0.0 );
	} else {
		anisotropyV /= material.anisotropy;
		material.anisotropy = saturate( material.anisotropy );
	}
	material.alphaT = mix( pow2( material.roughness ), 1.0, pow2( material.anisotropy ) );
	material.anisotropyT = tbn[ 0 ] * anisotropyV.x + tbn[ 1 ] * anisotropyV.y;
	material.anisotropyB = tbn[ 1 ] * anisotropyV.x - tbn[ 0 ] * anisotropyV.y;
#endif`,ls=`struct PhysicalMaterial {
	vec3 diffuseColor;
	float roughness;
	vec3 specularColor;
	float specularF90;
	float dispersion;
	#ifdef USE_CLEARCOAT
		float clearcoat;
		float clearcoatRoughness;
		vec3 clearcoatF0;
		float clearcoatF90;
	#endif
	#ifdef USE_IRIDESCENCE
		float iridescence;
		float iridescenceIOR;
		float iridescenceThickness;
		vec3 iridescenceFresnel;
		vec3 iridescenceF0;
	#endif
	#ifdef USE_SHEEN
		vec3 sheenColor;
		float sheenRoughness;
	#endif
	#ifdef IOR
		float ior;
	#endif
	#ifdef USE_TRANSMISSION
		float transmission;
		float transmissionAlpha;
		float thickness;
		float attenuationDistance;
		vec3 attenuationColor;
	#endif
	#ifdef USE_ANISOTROPY
		float anisotropy;
		float alphaT;
		vec3 anisotropyT;
		vec3 anisotropyB;
	#endif
};
vec3 clearcoatSpecularDirect = vec3( 0.0 );
vec3 clearcoatSpecularIndirect = vec3( 0.0 );
vec3 sheenSpecularDirect = vec3( 0.0 );
vec3 sheenSpecularIndirect = vec3(0.0 );
vec3 Schlick_to_F0( const in vec3 f, const in float f90, const in float dotVH ) {
    float x = clamp( 1.0 - dotVH, 0.0, 1.0 );
    float x2 = x * x;
    float x5 = clamp( x * x2 * x2, 0.0, 0.9999 );
    return ( f - vec3( f90 ) * x5 ) / ( 1.0 - x5 );
}
float V_GGX_SmithCorrelated( const in float alpha, const in float dotNL, const in float dotNV ) {
	float a2 = pow2( alpha );
	float gv = dotNL * sqrt( a2 + ( 1.0 - a2 ) * pow2( dotNV ) );
	float gl = dotNV * sqrt( a2 + ( 1.0 - a2 ) * pow2( dotNL ) );
	return 0.5 / max( gv + gl, EPSILON );
}
float D_GGX( const in float alpha, const in float dotNH ) {
	float a2 = pow2( alpha );
	float denom = pow2( dotNH ) * ( a2 - 1.0 ) + 1.0;
	return RECIPROCAL_PI * a2 / pow2( denom );
}
#ifdef USE_ANISOTROPY
	float V_GGX_SmithCorrelated_Anisotropic( const in float alphaT, const in float alphaB, const in float dotTV, const in float dotBV, const in float dotTL, const in float dotBL, const in float dotNV, const in float dotNL ) {
		float gv = dotNL * length( vec3( alphaT * dotTV, alphaB * dotBV, dotNV ) );
		float gl = dotNV * length( vec3( alphaT * dotTL, alphaB * dotBL, dotNL ) );
		float v = 0.5 / ( gv + gl );
		return saturate(v);
	}
	float D_GGX_Anisotropic( const in float alphaT, const in float alphaB, const in float dotNH, const in float dotTH, const in float dotBH ) {
		float a2 = alphaT * alphaB;
		highp vec3 v = vec3( alphaB * dotTH, alphaT * dotBH, a2 * dotNH );
		highp float v2 = dot( v, v );
		float w2 = a2 / v2;
		return RECIPROCAL_PI * a2 * pow2 ( w2 );
	}
#endif
#ifdef USE_CLEARCOAT
	vec3 BRDF_GGX_Clearcoat( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, const in PhysicalMaterial material) {
		vec3 f0 = material.clearcoatF0;
		float f90 = material.clearcoatF90;
		float roughness = material.clearcoatRoughness;
		float alpha = pow2( roughness );
		vec3 halfDir = normalize( lightDir + viewDir );
		float dotNL = saturate( dot( normal, lightDir ) );
		float dotNV = saturate( dot( normal, viewDir ) );
		float dotNH = saturate( dot( normal, halfDir ) );
		float dotVH = saturate( dot( viewDir, halfDir ) );
		vec3 F = F_Schlick( f0, f90, dotVH );
		float V = V_GGX_SmithCorrelated( alpha, dotNL, dotNV );
		float D = D_GGX( alpha, dotNH );
		return F * ( V * D );
	}
#endif
vec3 BRDF_GGX( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, const in PhysicalMaterial material ) {
	vec3 f0 = material.specularColor;
	float f90 = material.specularF90;
	float roughness = material.roughness;
	float alpha = pow2( roughness );
	vec3 halfDir = normalize( lightDir + viewDir );
	float dotNL = saturate( dot( normal, lightDir ) );
	float dotNV = saturate( dot( normal, viewDir ) );
	float dotNH = saturate( dot( normal, halfDir ) );
	float dotVH = saturate( dot( viewDir, halfDir ) );
	vec3 F = F_Schlick( f0, f90, dotVH );
	#ifdef USE_IRIDESCENCE
		F = mix( F, material.iridescenceFresnel, material.iridescence );
	#endif
	#ifdef USE_ANISOTROPY
		float dotTL = dot( material.anisotropyT, lightDir );
		float dotTV = dot( material.anisotropyT, viewDir );
		float dotTH = dot( material.anisotropyT, halfDir );
		float dotBL = dot( material.anisotropyB, lightDir );
		float dotBV = dot( material.anisotropyB, viewDir );
		float dotBH = dot( material.anisotropyB, halfDir );
		float V = V_GGX_SmithCorrelated_Anisotropic( material.alphaT, alpha, dotTV, dotBV, dotTL, dotBL, dotNV, dotNL );
		float D = D_GGX_Anisotropic( material.alphaT, alpha, dotNH, dotTH, dotBH );
	#else
		float V = V_GGX_SmithCorrelated( alpha, dotNL, dotNV );
		float D = D_GGX( alpha, dotNH );
	#endif
	return F * ( V * D );
}
vec2 LTC_Uv( const in vec3 N, const in vec3 V, const in float roughness ) {
	const float LUT_SIZE = 64.0;
	const float LUT_SCALE = ( LUT_SIZE - 1.0 ) / LUT_SIZE;
	const float LUT_BIAS = 0.5 / LUT_SIZE;
	float dotNV = saturate( dot( N, V ) );
	vec2 uv = vec2( roughness, sqrt( 1.0 - dotNV ) );
	uv = uv * LUT_SCALE + LUT_BIAS;
	return uv;
}
float LTC_ClippedSphereFormFactor( const in vec3 f ) {
	float l = length( f );
	return max( ( l * l + f.z ) / ( l + 1.0 ), 0.0 );
}
vec3 LTC_EdgeVectorFormFactor( const in vec3 v1, const in vec3 v2 ) {
	float x = dot( v1, v2 );
	float y = abs( x );
	float a = 0.8543985 + ( 0.4965155 + 0.0145206 * y ) * y;
	float b = 3.4175940 + ( 4.1616724 + y ) * y;
	float v = a / b;
	float theta_sintheta = ( x > 0.0 ) ? v : 0.5 * inversesqrt( max( 1.0 - x * x, 1e-7 ) ) - v;
	return cross( v1, v2 ) * theta_sintheta;
}
vec3 LTC_Evaluate( const in vec3 N, const in vec3 V, const in vec3 P, const in mat3 mInv, const in vec3 rectCoords[ 4 ] ) {
	vec3 v1 = rectCoords[ 1 ] - rectCoords[ 0 ];
	vec3 v2 = rectCoords[ 3 ] - rectCoords[ 0 ];
	vec3 lightNormal = cross( v1, v2 );
	if( dot( lightNormal, P - rectCoords[ 0 ] ) < 0.0 ) return vec3( 0.0 );
	vec3 T1, T2;
	T1 = normalize( V - N * dot( V, N ) );
	T2 = - cross( N, T1 );
	mat3 mat = mInv * transposeMat3( mat3( T1, T2, N ) );
	vec3 coords[ 4 ];
	coords[ 0 ] = mat * ( rectCoords[ 0 ] - P );
	coords[ 1 ] = mat * ( rectCoords[ 1 ] - P );
	coords[ 2 ] = mat * ( rectCoords[ 2 ] - P );
	coords[ 3 ] = mat * ( rectCoords[ 3 ] - P );
	coords[ 0 ] = normalize( coords[ 0 ] );
	coords[ 1 ] = normalize( coords[ 1 ] );
	coords[ 2 ] = normalize( coords[ 2 ] );
	coords[ 3 ] = normalize( coords[ 3 ] );
	vec3 vectorFormFactor = vec3( 0.0 );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 0 ], coords[ 1 ] );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 1 ], coords[ 2 ] );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 2 ], coords[ 3 ] );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 3 ], coords[ 0 ] );
	float result = LTC_ClippedSphereFormFactor( vectorFormFactor );
	return vec3( result );
}
#if defined( USE_SHEEN )
float D_Charlie( float roughness, float dotNH ) {
	float alpha = pow2( roughness );
	float invAlpha = 1.0 / alpha;
	float cos2h = dotNH * dotNH;
	float sin2h = max( 1.0 - cos2h, 0.0078125 );
	return ( 2.0 + invAlpha ) * pow( sin2h, invAlpha * 0.5 ) / ( 2.0 * PI );
}
float V_Neubelt( float dotNV, float dotNL ) {
	return saturate( 1.0 / ( 4.0 * ( dotNL + dotNV - dotNL * dotNV ) ) );
}
vec3 BRDF_Sheen( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, vec3 sheenColor, const in float sheenRoughness ) {
	vec3 halfDir = normalize( lightDir + viewDir );
	float dotNL = saturate( dot( normal, lightDir ) );
	float dotNV = saturate( dot( normal, viewDir ) );
	float dotNH = saturate( dot( normal, halfDir ) );
	float D = D_Charlie( sheenRoughness, dotNH );
	float V = V_Neubelt( dotNV, dotNL );
	return sheenColor * ( D * V );
}
#endif
float IBLSheenBRDF( const in vec3 normal, const in vec3 viewDir, const in float roughness ) {
	float dotNV = saturate( dot( normal, viewDir ) );
	float r2 = roughness * roughness;
	float a = roughness < 0.25 ? -339.2 * r2 + 161.4 * roughness - 25.9 : -8.48 * r2 + 14.3 * roughness - 9.95;
	float b = roughness < 0.25 ? 44.0 * r2 - 23.7 * roughness + 3.26 : 1.97 * r2 - 3.27 * roughness + 0.72;
	float DG = exp( a * dotNV + b ) + ( roughness < 0.25 ? 0.0 : 0.1 * ( roughness - 0.25 ) );
	return saturate( DG * RECIPROCAL_PI );
}
vec2 DFGApprox( const in vec3 normal, const in vec3 viewDir, const in float roughness ) {
	float dotNV = saturate( dot( normal, viewDir ) );
	const vec4 c0 = vec4( - 1, - 0.0275, - 0.572, 0.022 );
	const vec4 c1 = vec4( 1, 0.0425, 1.04, - 0.04 );
	vec4 r = roughness * c0 + c1;
	float a004 = min( r.x * r.x, exp2( - 9.28 * dotNV ) ) * r.x + r.y;
	vec2 fab = vec2( - 1.04, 1.04 ) * a004 + r.zw;
	return fab;
}
vec3 EnvironmentBRDF( const in vec3 normal, const in vec3 viewDir, const in vec3 specularColor, const in float specularF90, const in float roughness ) {
	vec2 fab = DFGApprox( normal, viewDir, roughness );
	return specularColor * fab.x + specularF90 * fab.y;
}
#ifdef USE_IRIDESCENCE
void computeMultiscatteringIridescence( const in vec3 normal, const in vec3 viewDir, const in vec3 specularColor, const in float specularF90, const in float iridescence, const in vec3 iridescenceF0, const in float roughness, inout vec3 singleScatter, inout vec3 multiScatter ) {
#else
void computeMultiscattering( const in vec3 normal, const in vec3 viewDir, const in vec3 specularColor, const in float specularF90, const in float roughness, inout vec3 singleScatter, inout vec3 multiScatter ) {
#endif
	vec2 fab = DFGApprox( normal, viewDir, roughness );
	#ifdef USE_IRIDESCENCE
		vec3 Fr = mix( specularColor, iridescenceF0, iridescence );
	#else
		vec3 Fr = specularColor;
	#endif
	vec3 FssEss = Fr * fab.x + specularF90 * fab.y;
	float Ess = fab.x + fab.y;
	float Ems = 1.0 - Ess;
	vec3 Favg = Fr + ( 1.0 - Fr ) * 0.047619;	vec3 Fms = FssEss * Favg / ( 1.0 - Ems * Favg );
	singleScatter += FssEss;
	multiScatter += Fms * Ems;
}
#if NUM_RECT_AREA_LIGHTS > 0
	void RE_Direct_RectArea_Physical( const in RectAreaLight rectAreaLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight ) {
		vec3 normal = geometryNormal;
		vec3 viewDir = geometryViewDir;
		vec3 position = geometryPosition;
		vec3 lightPos = rectAreaLight.position;
		vec3 halfWidth = rectAreaLight.halfWidth;
		vec3 halfHeight = rectAreaLight.halfHeight;
		vec3 lightColor = rectAreaLight.color;
		float roughness = material.roughness;
		vec3 rectCoords[ 4 ];
		rectCoords[ 0 ] = lightPos + halfWidth - halfHeight;		rectCoords[ 1 ] = lightPos - halfWidth - halfHeight;
		rectCoords[ 2 ] = lightPos - halfWidth + halfHeight;
		rectCoords[ 3 ] = lightPos + halfWidth + halfHeight;
		vec2 uv = LTC_Uv( normal, viewDir, roughness );
		vec4 t1 = texture2D( ltc_1, uv );
		vec4 t2 = texture2D( ltc_2, uv );
		mat3 mInv = mat3(
			vec3( t1.x, 0, t1.y ),
			vec3(    0, 1,    0 ),
			vec3( t1.z, 0, t1.w )
		);
		vec3 fresnel = ( material.specularColor * t2.x + ( vec3( 1.0 ) - material.specularColor ) * t2.y );
		reflectedLight.directSpecular += lightColor * fresnel * LTC_Evaluate( normal, viewDir, position, mInv, rectCoords );
		reflectedLight.directDiffuse += lightColor * material.diffuseColor * LTC_Evaluate( normal, viewDir, position, mat3( 1.0 ), rectCoords );
	}
#endif
void RE_Direct_Physical( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight ) {
	float dotNL = saturate( dot( geometryNormal, directLight.direction ) );
	vec3 irradiance = dotNL * directLight.color;
	#ifdef USE_CLEARCOAT
		float dotNLcc = saturate( dot( geometryClearcoatNormal, directLight.direction ) );
		vec3 ccIrradiance = dotNLcc * directLight.color;
		clearcoatSpecularDirect += ccIrradiance * BRDF_GGX_Clearcoat( directLight.direction, geometryViewDir, geometryClearcoatNormal, material );
	#endif
	#ifdef USE_SHEEN
		sheenSpecularDirect += irradiance * BRDF_Sheen( directLight.direction, geometryViewDir, geometryNormal, material.sheenColor, material.sheenRoughness );
	#endif
	reflectedLight.directSpecular += irradiance * BRDF_GGX( directLight.direction, geometryViewDir, geometryNormal, material );
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectDiffuse_Physical( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectSpecular_Physical( const in vec3 radiance, const in vec3 irradiance, const in vec3 clearcoatRadiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight) {
	#ifdef USE_CLEARCOAT
		clearcoatSpecularIndirect += clearcoatRadiance * EnvironmentBRDF( geometryClearcoatNormal, geometryViewDir, material.clearcoatF0, material.clearcoatF90, material.clearcoatRoughness );
	#endif
	#ifdef USE_SHEEN
		sheenSpecularIndirect += irradiance * material.sheenColor * IBLSheenBRDF( geometryNormal, geometryViewDir, material.sheenRoughness );
	#endif
	vec3 singleScattering = vec3( 0.0 );
	vec3 multiScattering = vec3( 0.0 );
	vec3 cosineWeightedIrradiance = irradiance * RECIPROCAL_PI;
	#ifdef USE_IRIDESCENCE
		computeMultiscatteringIridescence( geometryNormal, geometryViewDir, material.specularColor, material.specularF90, material.iridescence, material.iridescenceFresnel, material.roughness, singleScattering, multiScattering );
	#else
		computeMultiscattering( geometryNormal, geometryViewDir, material.specularColor, material.specularF90, material.roughness, singleScattering, multiScattering );
	#endif
	vec3 totalScattering = singleScattering + multiScattering;
	vec3 diffuse = material.diffuseColor * ( 1.0 - max( max( totalScattering.r, totalScattering.g ), totalScattering.b ) );
	reflectedLight.indirectSpecular += radiance * singleScattering;
	reflectedLight.indirectSpecular += multiScattering * cosineWeightedIrradiance;
	reflectedLight.indirectDiffuse += diffuse * cosineWeightedIrradiance;
}
#define RE_Direct				RE_Direct_Physical
#define RE_Direct_RectArea		RE_Direct_RectArea_Physical
#define RE_IndirectDiffuse		RE_IndirectDiffuse_Physical
#define RE_IndirectSpecular		RE_IndirectSpecular_Physical
float computeSpecularOcclusion( const in float dotNV, const in float ambientOcclusion, const in float roughness ) {
	return saturate( pow( dotNV + ambientOcclusion, exp2( - 16.0 * roughness - 1.0 ) ) - 1.0 + ambientOcclusion );
}`,fs=`
vec3 geometryPosition = - vViewPosition;
vec3 geometryNormal = normal;
vec3 geometryViewDir = ( isOrthographic ) ? vec3( 0, 0, 1 ) : normalize( vViewPosition );
vec3 geometryClearcoatNormal = vec3( 0.0 );
#ifdef USE_CLEARCOAT
	geometryClearcoatNormal = clearcoatNormal;
#endif
#ifdef USE_IRIDESCENCE
	float dotNVi = saturate( dot( normal, geometryViewDir ) );
	if ( material.iridescenceThickness == 0.0 ) {
		material.iridescence = 0.0;
	} else {
		material.iridescence = saturate( material.iridescence );
	}
	if ( material.iridescence > 0.0 ) {
		material.iridescenceFresnel = evalIridescence( 1.0, material.iridescenceIOR, dotNVi, material.iridescenceThickness, material.specularColor );
		material.iridescenceF0 = Schlick_to_F0( material.iridescenceFresnel, 1.0, dotNVi );
	}
#endif
IncidentLight directLight;
#if ( NUM_POINT_LIGHTS > 0 ) && defined( RE_Direct )
	PointLight pointLight;
	#if defined( USE_SHADOWMAP ) && NUM_POINT_LIGHT_SHADOWS > 0
	PointLightShadow pointLightShadow;
	#endif
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_POINT_LIGHTS; i ++ ) {
		pointLight = pointLights[ i ];
		getPointLightInfo( pointLight, geometryPosition, directLight );
		#if defined( USE_SHADOWMAP ) && ( UNROLLED_LOOP_INDEX < NUM_POINT_LIGHT_SHADOWS )
		pointLightShadow = pointLightShadows[ i ];
		directLight.color *= ( directLight.visible && receiveShadow ) ? getPointShadow( pointShadowMap[ i ], pointLightShadow.shadowMapSize, pointLightShadow.shadowIntensity, pointLightShadow.shadowBias, pointLightShadow.shadowRadius, vPointShadowCoord[ i ], pointLightShadow.shadowCameraNear, pointLightShadow.shadowCameraFar ) : 1.0;
		#endif
		RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if ( NUM_SPOT_LIGHTS > 0 ) && defined( RE_Direct )
	SpotLight spotLight;
	vec4 spotColor;
	vec3 spotLightCoord;
	bool inSpotLightMap;
	#if defined( USE_SHADOWMAP ) && NUM_SPOT_LIGHT_SHADOWS > 0
	SpotLightShadow spotLightShadow;
	#endif
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_SPOT_LIGHTS; i ++ ) {
		spotLight = spotLights[ i ];
		getSpotLightInfo( spotLight, geometryPosition, directLight );
		#if ( UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS_WITH_MAPS )
		#define SPOT_LIGHT_MAP_INDEX UNROLLED_LOOP_INDEX
		#elif ( UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS )
		#define SPOT_LIGHT_MAP_INDEX NUM_SPOT_LIGHT_MAPS
		#else
		#define SPOT_LIGHT_MAP_INDEX ( UNROLLED_LOOP_INDEX - NUM_SPOT_LIGHT_SHADOWS + NUM_SPOT_LIGHT_SHADOWS_WITH_MAPS )
		#endif
		#if ( SPOT_LIGHT_MAP_INDEX < NUM_SPOT_LIGHT_MAPS )
			spotLightCoord = vSpotLightCoord[ i ].xyz / vSpotLightCoord[ i ].w;
			inSpotLightMap = all( lessThan( abs( spotLightCoord * 2. - 1. ), vec3( 1.0 ) ) );
			spotColor = texture2D( spotLightMap[ SPOT_LIGHT_MAP_INDEX ], spotLightCoord.xy );
			directLight.color = inSpotLightMap ? directLight.color * spotColor.rgb : directLight.color;
		#endif
		#undef SPOT_LIGHT_MAP_INDEX
		#if defined( USE_SHADOWMAP ) && ( UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS )
		spotLightShadow = spotLightShadows[ i ];
		directLight.color *= ( directLight.visible && receiveShadow ) ? getShadow( spotShadowMap[ i ], spotLightShadow.shadowMapSize, spotLightShadow.shadowIntensity, spotLightShadow.shadowBias, spotLightShadow.shadowRadius, vSpotLightCoord[ i ] ) : 1.0;
		#endif
		RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if ( NUM_DIR_LIGHTS > 0 ) && defined( RE_Direct )
	DirectionalLight directionalLight;
	#if defined( USE_SHADOWMAP ) && NUM_DIR_LIGHT_SHADOWS > 0
	DirectionalLightShadow directionalLightShadow;
	#endif
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_DIR_LIGHTS; i ++ ) {
		directionalLight = directionalLights[ i ];
		getDirectionalLightInfo( directionalLight, directLight );
		#if defined( USE_SHADOWMAP ) && ( UNROLLED_LOOP_INDEX < NUM_DIR_LIGHT_SHADOWS )
		directionalLightShadow = directionalLightShadows[ i ];
		directLight.color *= ( directLight.visible && receiveShadow ) ? getShadow( directionalShadowMap[ i ], directionalLightShadow.shadowMapSize, directionalLightShadow.shadowIntensity, directionalLightShadow.shadowBias, directionalLightShadow.shadowRadius, vDirectionalShadowCoord[ i ] ) : 1.0;
		#endif
		RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if ( NUM_RECT_AREA_LIGHTS > 0 ) && defined( RE_Direct_RectArea )
	RectAreaLight rectAreaLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_RECT_AREA_LIGHTS; i ++ ) {
		rectAreaLight = rectAreaLights[ i ];
		RE_Direct_RectArea( rectAreaLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if defined( RE_IndirectDiffuse )
	vec3 iblIrradiance = vec3( 0.0 );
	vec3 irradiance = getAmbientLightIrradiance( ambientLightColor );
	#if defined( USE_LIGHT_PROBES )
		irradiance += getLightProbeIrradiance( lightProbe, geometryNormal );
	#endif
	#if ( NUM_HEMI_LIGHTS > 0 )
		#pragma unroll_loop_start
		for ( int i = 0; i < NUM_HEMI_LIGHTS; i ++ ) {
			irradiance += getHemisphereLightIrradiance( hemisphereLights[ i ], geometryNormal );
		}
		#pragma unroll_loop_end
	#endif
#endif
#if defined( RE_IndirectSpecular )
	vec3 radiance = vec3( 0.0 );
	vec3 clearcoatRadiance = vec3( 0.0 );
#endif`,ds=`#if defined( RE_IndirectDiffuse )
	#ifdef USE_LIGHTMAP
		vec4 lightMapTexel = texture2D( lightMap, vLightMapUv );
		vec3 lightMapIrradiance = lightMapTexel.rgb * lightMapIntensity;
		irradiance += lightMapIrradiance;
	#endif
	#if defined( USE_ENVMAP ) && defined( STANDARD ) && defined( ENVMAP_TYPE_CUBE_UV )
		iblIrradiance += getIBLIrradiance( geometryNormal );
	#endif
#endif
#if defined( USE_ENVMAP ) && defined( RE_IndirectSpecular )
	#ifdef USE_ANISOTROPY
		radiance += getIBLAnisotropyRadiance( geometryViewDir, geometryNormal, material.roughness, material.anisotropyB, material.anisotropy );
	#else
		radiance += getIBLRadiance( geometryViewDir, geometryNormal, material.roughness );
	#endif
	#ifdef USE_CLEARCOAT
		clearcoatRadiance += getIBLRadiance( geometryViewDir, geometryClearcoatNormal, material.clearcoatRoughness );
	#endif
#endif`,us=`#if defined( RE_IndirectDiffuse )
	RE_IndirectDiffuse( irradiance, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
#endif
#if defined( RE_IndirectSpecular )
	RE_IndirectSpecular( radiance, iblIrradiance, clearcoatRadiance, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
#endif`,ps=`#if defined( USE_LOGDEPTHBUF )
	gl_FragDepth = vIsPerspective == 0.0 ? gl_FragCoord.z : log2( vFragDepth ) * logDepthBufFC * 0.5;
#endif`,hs=`#if defined( USE_LOGDEPTHBUF )
	uniform float logDepthBufFC;
	varying float vFragDepth;
	varying float vIsPerspective;
#endif`,ms=`#ifdef USE_LOGDEPTHBUF
	varying float vFragDepth;
	varying float vIsPerspective;
#endif`,_s=`#ifdef USE_LOGDEPTHBUF
	vFragDepth = 1.0 + gl_Position.w;
	vIsPerspective = float( isPerspectiveMatrix( projectionMatrix ) );
#endif`,vs=`#ifdef USE_MAP
	vec4 sampledDiffuseColor = texture2D( map, vMapUv );
	#ifdef DECODE_VIDEO_TEXTURE
		sampledDiffuseColor = sRGBTransferEOTF( sampledDiffuseColor );
	#endif
	diffuseColor *= sampledDiffuseColor;
#endif`,gs=`#ifdef USE_MAP
	uniform sampler2D map;
#endif`,Ss=`#if defined( USE_MAP ) || defined( USE_ALPHAMAP )
	#if defined( USE_POINTS_UV )
		vec2 uv = vUv;
	#else
		vec2 uv = ( uvTransform * vec3( gl_PointCoord.x, 1.0 - gl_PointCoord.y, 1 ) ).xy;
	#endif
#endif
#ifdef USE_MAP
	diffuseColor *= texture2D( map, uv );
#endif
#ifdef USE_ALPHAMAP
	diffuseColor.a *= texture2D( alphaMap, uv ).g;
#endif`,Es=`#if defined( USE_POINTS_UV )
	varying vec2 vUv;
#else
	#if defined( USE_MAP ) || defined( USE_ALPHAMAP )
		uniform mat3 uvTransform;
	#endif
#endif
#ifdef USE_MAP
	uniform sampler2D map;
#endif
#ifdef USE_ALPHAMAP
	uniform sampler2D alphaMap;
#endif`,Ms=`float metalnessFactor = metalness;
#ifdef USE_METALNESSMAP
	vec4 texelMetalness = texture2D( metalnessMap, vMetalnessMapUv );
	metalnessFactor *= texelMetalness.b;
#endif`,Ts=`#ifdef USE_METALNESSMAP
	uniform sampler2D metalnessMap;
#endif`,xs=`#ifdef USE_INSTANCING_MORPH
	float morphTargetInfluences[ MORPHTARGETS_COUNT ];
	float morphTargetBaseInfluence = texelFetch( morphTexture, ivec2( 0, gl_InstanceID ), 0 ).r;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		morphTargetInfluences[i] =  texelFetch( morphTexture, ivec2( i + 1, gl_InstanceID ), 0 ).r;
	}
#endif`,As=`#if defined( USE_MORPHCOLORS )
	vColor *= morphTargetBaseInfluence;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		#if defined( USE_COLOR_ALPHA )
			if ( morphTargetInfluences[ i ] != 0.0 ) vColor += getMorph( gl_VertexID, i, 2 ) * morphTargetInfluences[ i ];
		#elif defined( USE_COLOR )
			if ( morphTargetInfluences[ i ] != 0.0 ) vColor += getMorph( gl_VertexID, i, 2 ).rgb * morphTargetInfluences[ i ];
		#endif
	}
#endif`,Rs=`#ifdef USE_MORPHNORMALS
	objectNormal *= morphTargetBaseInfluence;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		if ( morphTargetInfluences[ i ] != 0.0 ) objectNormal += getMorph( gl_VertexID, i, 1 ).xyz * morphTargetInfluences[ i ];
	}
#endif`,Cs=`#ifdef USE_MORPHTARGETS
	#ifndef USE_INSTANCING_MORPH
		uniform float morphTargetBaseInfluence;
		uniform float morphTargetInfluences[ MORPHTARGETS_COUNT ];
	#endif
	uniform sampler2DArray morphTargetsTexture;
	uniform ivec2 morphTargetsTextureSize;
	vec4 getMorph( const in int vertexIndex, const in int morphTargetIndex, const in int offset ) {
		int texelIndex = vertexIndex * MORPHTARGETS_TEXTURE_STRIDE + offset;
		int y = texelIndex / morphTargetsTextureSize.x;
		int x = texelIndex - y * morphTargetsTextureSize.x;
		ivec3 morphUV = ivec3( x, y, morphTargetIndex );
		return texelFetch( morphTargetsTexture, morphUV, 0 );
	}
#endif`,bs=`#ifdef USE_MORPHTARGETS
	transformed *= morphTargetBaseInfluence;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		if ( morphTargetInfluences[ i ] != 0.0 ) transformed += getMorph( gl_VertexID, i, 0 ).xyz * morphTargetInfluences[ i ];
	}
#endif`,Ps=`float faceDirection = gl_FrontFacing ? 1.0 : - 1.0;
#ifdef FLAT_SHADED
	vec3 fdx = dFdx( vViewPosition );
	vec3 fdy = dFdy( vViewPosition );
	vec3 normal = normalize( cross( fdx, fdy ) );
#else
	vec3 normal = normalize( vNormal );
	#ifdef DOUBLE_SIDED
		normal *= faceDirection;
	#endif
#endif
#if defined( USE_NORMALMAP_TANGENTSPACE ) || defined( USE_CLEARCOAT_NORMALMAP ) || defined( USE_ANISOTROPY )
	#ifdef USE_TANGENT
		mat3 tbn = mat3( normalize( vTangent ), normalize( vBitangent ), normal );
	#else
		mat3 tbn = getTangentFrame( - vViewPosition, normal,
		#if defined( USE_NORMALMAP )
			vNormalMapUv
		#elif defined( USE_CLEARCOAT_NORMALMAP )
			vClearcoatNormalMapUv
		#else
			vUv
		#endif
		);
	#endif
	#if defined( DOUBLE_SIDED ) && ! defined( FLAT_SHADED )
		tbn[0] *= faceDirection;
		tbn[1] *= faceDirection;
	#endif
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	#ifdef USE_TANGENT
		mat3 tbn2 = mat3( normalize( vTangent ), normalize( vBitangent ), normal );
	#else
		mat3 tbn2 = getTangentFrame( - vViewPosition, normal, vClearcoatNormalMapUv );
	#endif
	#if defined( DOUBLE_SIDED ) && ! defined( FLAT_SHADED )
		tbn2[0] *= faceDirection;
		tbn2[1] *= faceDirection;
	#endif
#endif
vec3 nonPerturbedNormal = normal;`,Ls=`#ifdef USE_NORMALMAP_OBJECTSPACE
	normal = texture2D( normalMap, vNormalMapUv ).xyz * 2.0 - 1.0;
	#ifdef FLIP_SIDED
		normal = - normal;
	#endif
	#ifdef DOUBLE_SIDED
		normal = normal * faceDirection;
	#endif
	normal = normalize( normalMatrix * normal );
#elif defined( USE_NORMALMAP_TANGENTSPACE )
	vec3 mapN = texture2D( normalMap, vNormalMapUv ).xyz * 2.0 - 1.0;
	mapN.xy *= normalScale;
	normal = normalize( tbn * mapN );
#elif defined( USE_BUMPMAP )
	normal = perturbNormalArb( - vViewPosition, normal, dHdxy_fwd(), faceDirection );
#endif`,Us=`#ifndef FLAT_SHADED
	varying vec3 vNormal;
	#ifdef USE_TANGENT
		varying vec3 vTangent;
		varying vec3 vBitangent;
	#endif
#endif`,Ds=`#ifndef FLAT_SHADED
	varying vec3 vNormal;
	#ifdef USE_TANGENT
		varying vec3 vTangent;
		varying vec3 vBitangent;
	#endif
#endif`,ws=`#ifndef FLAT_SHADED
	vNormal = normalize( transformedNormal );
	#ifdef USE_TANGENT
		vTangent = normalize( transformedTangent );
		vBitangent = normalize( cross( vNormal, vTangent ) * tangent.w );
	#endif
#endif`,Is=`#ifdef USE_NORMALMAP
	uniform sampler2D normalMap;
	uniform vec2 normalScale;
#endif
#ifdef USE_NORMALMAP_OBJECTSPACE
	uniform mat3 normalMatrix;
#endif
#if ! defined ( USE_TANGENT ) && ( defined ( USE_NORMALMAP_TANGENTSPACE ) || defined ( USE_CLEARCOAT_NORMALMAP ) || defined( USE_ANISOTROPY ) )
	mat3 getTangentFrame( vec3 eye_pos, vec3 surf_norm, vec2 uv ) {
		vec3 q0 = dFdx( eye_pos.xyz );
		vec3 q1 = dFdy( eye_pos.xyz );
		vec2 st0 = dFdx( uv.st );
		vec2 st1 = dFdy( uv.st );
		vec3 N = surf_norm;
		vec3 q1perp = cross( q1, N );
		vec3 q0perp = cross( N, q0 );
		vec3 T = q1perp * st0.x + q0perp * st1.x;
		vec3 B = q1perp * st0.y + q0perp * st1.y;
		float det = max( dot( T, T ), dot( B, B ) );
		float scale = ( det == 0.0 ) ? 0.0 : inversesqrt( det );
		return mat3( T * scale, B * scale, N );
	}
#endif`,ys=`#ifdef USE_CLEARCOAT
	vec3 clearcoatNormal = nonPerturbedNormal;
#endif`,Ns=`#ifdef USE_CLEARCOAT_NORMALMAP
	vec3 clearcoatMapN = texture2D( clearcoatNormalMap, vClearcoatNormalMapUv ).xyz * 2.0 - 1.0;
	clearcoatMapN.xy *= clearcoatNormalScale;
	clearcoatNormal = normalize( tbn2 * clearcoatMapN );
#endif`,Os=`#ifdef USE_CLEARCOATMAP
	uniform sampler2D clearcoatMap;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	uniform sampler2D clearcoatNormalMap;
	uniform vec2 clearcoatNormalScale;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	uniform sampler2D clearcoatRoughnessMap;
#endif`,Fs=`#ifdef USE_IRIDESCENCEMAP
	uniform sampler2D iridescenceMap;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	uniform sampler2D iridescenceThicknessMap;
#endif`,Bs=`#ifdef OPAQUE
diffuseColor.a = 1.0;
#endif
#ifdef USE_TRANSMISSION
diffuseColor.a *= material.transmissionAlpha;
#endif
gl_FragColor = vec4( outgoingLight, diffuseColor.a );`,Gs=`vec3 packNormalToRGB( const in vec3 normal ) {
	return normalize( normal ) * 0.5 + 0.5;
}
vec3 unpackRGBToNormal( const in vec3 rgb ) {
	return 2.0 * rgb.xyz - 1.0;
}
const float PackUpscale = 256. / 255.;const float UnpackDownscale = 255. / 256.;const float ShiftRight8 = 1. / 256.;
const float Inv255 = 1. / 255.;
const vec4 PackFactors = vec4( 1.0, 256.0, 256.0 * 256.0, 256.0 * 256.0 * 256.0 );
const vec2 UnpackFactors2 = vec2( UnpackDownscale, 1.0 / PackFactors.g );
const vec3 UnpackFactors3 = vec3( UnpackDownscale / PackFactors.rg, 1.0 / PackFactors.b );
const vec4 UnpackFactors4 = vec4( UnpackDownscale / PackFactors.rgb, 1.0 / PackFactors.a );
vec4 packDepthToRGBA( const in float v ) {
	if( v <= 0.0 )
		return vec4( 0., 0., 0., 0. );
	if( v >= 1.0 )
		return vec4( 1., 1., 1., 1. );
	float vuf;
	float af = modf( v * PackFactors.a, vuf );
	float bf = modf( vuf * ShiftRight8, vuf );
	float gf = modf( vuf * ShiftRight8, vuf );
	return vec4( vuf * Inv255, gf * PackUpscale, bf * PackUpscale, af );
}
vec3 packDepthToRGB( const in float v ) {
	if( v <= 0.0 )
		return vec3( 0., 0., 0. );
	if( v >= 1.0 )
		return vec3( 1., 1., 1. );
	float vuf;
	float bf = modf( v * PackFactors.b, vuf );
	float gf = modf( vuf * ShiftRight8, vuf );
	return vec3( vuf * Inv255, gf * PackUpscale, bf );
}
vec2 packDepthToRG( const in float v ) {
	if( v <= 0.0 )
		return vec2( 0., 0. );
	if( v >= 1.0 )
		return vec2( 1., 1. );
	float vuf;
	float gf = modf( v * 256., vuf );
	return vec2( vuf * Inv255, gf );
}
float unpackRGBAToDepth( const in vec4 v ) {
	return dot( v, UnpackFactors4 );
}
float unpackRGBToDepth( const in vec3 v ) {
	return dot( v, UnpackFactors3 );
}
float unpackRGToDepth( const in vec2 v ) {
	return v.r * UnpackFactors2.r + v.g * UnpackFactors2.g;
}
vec4 pack2HalfToRGBA( const in vec2 v ) {
	vec4 r = vec4( v.x, fract( v.x * 255.0 ), v.y, fract( v.y * 255.0 ) );
	return vec4( r.x - r.y / 255.0, r.y, r.z - r.w / 255.0, r.w );
}
vec2 unpackRGBATo2Half( const in vec4 v ) {
	return vec2( v.x + ( v.y / 255.0 ), v.z + ( v.w / 255.0 ) );
}
float viewZToOrthographicDepth( const in float viewZ, const in float near, const in float far ) {
	return ( viewZ + near ) / ( near - far );
}
float orthographicDepthToViewZ( const in float depth, const in float near, const in float far ) {
	return depth * ( near - far ) - near;
}
float viewZToPerspectiveDepth( const in float viewZ, const in float near, const in float far ) {
	return ( ( near + viewZ ) * far ) / ( ( far - near ) * viewZ );
}
float perspectiveDepthToViewZ( const in float depth, const in float near, const in float far ) {
	return ( near * far ) / ( ( far - near ) * depth - far );
}`,Hs=`#ifdef PREMULTIPLIED_ALPHA
	gl_FragColor.rgb *= gl_FragColor.a;
#endif`,Vs=`vec4 mvPosition = vec4( transformed, 1.0 );
#ifdef USE_BATCHING
	mvPosition = batchingMatrix * mvPosition;
#endif
#ifdef USE_INSTANCING
	mvPosition = instanceMatrix * mvPosition;
#endif
mvPosition = modelViewMatrix * mvPosition;
gl_Position = projectionMatrix * mvPosition;`,ks=`#ifdef DITHERING
	gl_FragColor.rgb = dithering( gl_FragColor.rgb );
#endif`,zs=`#ifdef DITHERING
	vec3 dithering( vec3 color ) {
		float grid_position = rand( gl_FragCoord.xy );
		vec3 dither_shift_RGB = vec3( 0.25 / 255.0, -0.25 / 255.0, 0.25 / 255.0 );
		dither_shift_RGB = mix( 2.0 * dither_shift_RGB, -2.0 * dither_shift_RGB, grid_position );
		return color + dither_shift_RGB;
	}
#endif`,Ws=`float roughnessFactor = roughness;
#ifdef USE_ROUGHNESSMAP
	vec4 texelRoughness = texture2D( roughnessMap, vRoughnessMapUv );
	roughnessFactor *= texelRoughness.g;
#endif`,Xs=`#ifdef USE_ROUGHNESSMAP
	uniform sampler2D roughnessMap;
#endif`,Ks=`#if NUM_SPOT_LIGHT_COORDS > 0
	varying vec4 vSpotLightCoord[ NUM_SPOT_LIGHT_COORDS ];
#endif
#if NUM_SPOT_LIGHT_MAPS > 0
	uniform sampler2D spotLightMap[ NUM_SPOT_LIGHT_MAPS ];
#endif
#ifdef USE_SHADOWMAP
	#if NUM_DIR_LIGHT_SHADOWS > 0
		uniform sampler2D directionalShadowMap[ NUM_DIR_LIGHT_SHADOWS ];
		varying vec4 vDirectionalShadowCoord[ NUM_DIR_LIGHT_SHADOWS ];
		struct DirectionalLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform DirectionalLightShadow directionalLightShadows[ NUM_DIR_LIGHT_SHADOWS ];
	#endif
	#if NUM_SPOT_LIGHT_SHADOWS > 0
		uniform sampler2D spotShadowMap[ NUM_SPOT_LIGHT_SHADOWS ];
		struct SpotLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform SpotLightShadow spotLightShadows[ NUM_SPOT_LIGHT_SHADOWS ];
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
		uniform sampler2D pointShadowMap[ NUM_POINT_LIGHT_SHADOWS ];
		varying vec4 vPointShadowCoord[ NUM_POINT_LIGHT_SHADOWS ];
		struct PointLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
			float shadowCameraNear;
			float shadowCameraFar;
		};
		uniform PointLightShadow pointLightShadows[ NUM_POINT_LIGHT_SHADOWS ];
	#endif
	float texture2DCompare( sampler2D depths, vec2 uv, float compare ) {
		return step( compare, unpackRGBAToDepth( texture2D( depths, uv ) ) );
	}
	vec2 texture2DDistribution( sampler2D shadow, vec2 uv ) {
		return unpackRGBATo2Half( texture2D( shadow, uv ) );
	}
	float VSMShadow (sampler2D shadow, vec2 uv, float compare ){
		float occlusion = 1.0;
		vec2 distribution = texture2DDistribution( shadow, uv );
		float hard_shadow = step( compare , distribution.x );
		if (hard_shadow != 1.0 ) {
			float distance = compare - distribution.x ;
			float variance = max( 0.00000, distribution.y * distribution.y );
			float softness_probability = variance / (variance + distance * distance );			softness_probability = clamp( ( softness_probability - 0.3 ) / ( 0.95 - 0.3 ), 0.0, 1.0 );			occlusion = clamp( max( hard_shadow, softness_probability ), 0.0, 1.0 );
		}
		return occlusion;
	}
	float getShadow( sampler2D shadowMap, vec2 shadowMapSize, float shadowIntensity, float shadowBias, float shadowRadius, vec4 shadowCoord ) {
		float shadow = 1.0;
		shadowCoord.xyz /= shadowCoord.w;
		shadowCoord.z += shadowBias;
		bool inFrustum = shadowCoord.x >= 0.0 && shadowCoord.x <= 1.0 && shadowCoord.y >= 0.0 && shadowCoord.y <= 1.0;
		bool frustumTest = inFrustum && shadowCoord.z <= 1.0;
		if ( frustumTest ) {
		#if defined( SHADOWMAP_TYPE_PCF )
			vec2 texelSize = vec2( 1.0 ) / shadowMapSize;
			float dx0 = - texelSize.x * shadowRadius;
			float dy0 = - texelSize.y * shadowRadius;
			float dx1 = + texelSize.x * shadowRadius;
			float dy1 = + texelSize.y * shadowRadius;
			float dx2 = dx0 / 2.0;
			float dy2 = dy0 / 2.0;
			float dx3 = dx1 / 2.0;
			float dy3 = dy1 / 2.0;
			shadow = (
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx2, dy2 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy2 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx3, dy2 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx2, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy, shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx3, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx2, dy3 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy3 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx3, dy3 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, dy1 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy1 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, dy1 ), shadowCoord.z )
			) * ( 1.0 / 17.0 );
		#elif defined( SHADOWMAP_TYPE_PCF_SOFT )
			vec2 texelSize = vec2( 1.0 ) / shadowMapSize;
			float dx = texelSize.x;
			float dy = texelSize.y;
			vec2 uv = shadowCoord.xy;
			vec2 f = fract( uv * shadowMapSize + 0.5 );
			uv -= f * texelSize;
			shadow = (
				texture2DCompare( shadowMap, uv, shadowCoord.z ) +
				texture2DCompare( shadowMap, uv + vec2( dx, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, uv + vec2( 0.0, dy ), shadowCoord.z ) +
				texture2DCompare( shadowMap, uv + texelSize, shadowCoord.z ) +
				mix( texture2DCompare( shadowMap, uv + vec2( -dx, 0.0 ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, 0.0 ), shadowCoord.z ),
					 f.x ) +
				mix( texture2DCompare( shadowMap, uv + vec2( -dx, dy ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, dy ), shadowCoord.z ),
					 f.x ) +
				mix( texture2DCompare( shadowMap, uv + vec2( 0.0, -dy ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( 0.0, 2.0 * dy ), shadowCoord.z ),
					 f.y ) +
				mix( texture2DCompare( shadowMap, uv + vec2( dx, -dy ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( dx, 2.0 * dy ), shadowCoord.z ),
					 f.y ) +
				mix( mix( texture2DCompare( shadowMap, uv + vec2( -dx, -dy ), shadowCoord.z ),
						  texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, -dy ), shadowCoord.z ),
						  f.x ),
					 mix( texture2DCompare( shadowMap, uv + vec2( -dx, 2.0 * dy ), shadowCoord.z ),
						  texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, 2.0 * dy ), shadowCoord.z ),
						  f.x ),
					 f.y )
			) * ( 1.0 / 9.0 );
		#elif defined( SHADOWMAP_TYPE_VSM )
			shadow = VSMShadow( shadowMap, shadowCoord.xy, shadowCoord.z );
		#else
			shadow = texture2DCompare( shadowMap, shadowCoord.xy, shadowCoord.z );
		#endif
		}
		return mix( 1.0, shadow, shadowIntensity );
	}
	vec2 cubeToUV( vec3 v, float texelSizeY ) {
		vec3 absV = abs( v );
		float scaleToCube = 1.0 / max( absV.x, max( absV.y, absV.z ) );
		absV *= scaleToCube;
		v *= scaleToCube * ( 1.0 - 2.0 * texelSizeY );
		vec2 planar = v.xy;
		float almostATexel = 1.5 * texelSizeY;
		float almostOne = 1.0 - almostATexel;
		if ( absV.z >= almostOne ) {
			if ( v.z > 0.0 )
				planar.x = 4.0 - v.x;
		} else if ( absV.x >= almostOne ) {
			float signX = sign( v.x );
			planar.x = v.z * signX + 2.0 * signX;
		} else if ( absV.y >= almostOne ) {
			float signY = sign( v.y );
			planar.x = v.x + 2.0 * signY + 2.0;
			planar.y = v.z * signY - 2.0;
		}
		return vec2( 0.125, 0.25 ) * planar + vec2( 0.375, 0.75 );
	}
	float getPointShadow( sampler2D shadowMap, vec2 shadowMapSize, float shadowIntensity, float shadowBias, float shadowRadius, vec4 shadowCoord, float shadowCameraNear, float shadowCameraFar ) {
		float shadow = 1.0;
		vec3 lightToPosition = shadowCoord.xyz;

		float lightToPositionLength = length( lightToPosition );
		if ( lightToPositionLength - shadowCameraFar <= 0.0 && lightToPositionLength - shadowCameraNear >= 0.0 ) {
			float dp = ( lightToPositionLength - shadowCameraNear ) / ( shadowCameraFar - shadowCameraNear );			dp += shadowBias;
			vec3 bd3D = normalize( lightToPosition );
			vec2 texelSize = vec2( 1.0 ) / ( shadowMapSize * vec2( 4.0, 2.0 ) );
			#if defined( SHADOWMAP_TYPE_PCF ) || defined( SHADOWMAP_TYPE_PCF_SOFT ) || defined( SHADOWMAP_TYPE_VSM )
				vec2 offset = vec2( - 1, 1 ) * shadowRadius * texelSize.y;
				shadow = (
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xyy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yyy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xyx, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yyx, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xxy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yxy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xxx, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yxx, texelSize.y ), dp )
				) * ( 1.0 / 9.0 );
			#else
				shadow = texture2DCompare( shadowMap, cubeToUV( bd3D, texelSize.y ), dp );
			#endif
		}
		return mix( 1.0, shadow, shadowIntensity );
	}
#endif`,Ys=`#if NUM_SPOT_LIGHT_COORDS > 0
	uniform mat4 spotLightMatrix[ NUM_SPOT_LIGHT_COORDS ];
	varying vec4 vSpotLightCoord[ NUM_SPOT_LIGHT_COORDS ];
#endif
#ifdef USE_SHADOWMAP
	#if NUM_DIR_LIGHT_SHADOWS > 0
		uniform mat4 directionalShadowMatrix[ NUM_DIR_LIGHT_SHADOWS ];
		varying vec4 vDirectionalShadowCoord[ NUM_DIR_LIGHT_SHADOWS ];
		struct DirectionalLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform DirectionalLightShadow directionalLightShadows[ NUM_DIR_LIGHT_SHADOWS ];
	#endif
	#if NUM_SPOT_LIGHT_SHADOWS > 0
		struct SpotLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform SpotLightShadow spotLightShadows[ NUM_SPOT_LIGHT_SHADOWS ];
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
		uniform mat4 pointShadowMatrix[ NUM_POINT_LIGHT_SHADOWS ];
		varying vec4 vPointShadowCoord[ NUM_POINT_LIGHT_SHADOWS ];
		struct PointLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
			float shadowCameraNear;
			float shadowCameraFar;
		};
		uniform PointLightShadow pointLightShadows[ NUM_POINT_LIGHT_SHADOWS ];
	#endif
#endif`,qs=`#if ( defined( USE_SHADOWMAP ) && ( NUM_DIR_LIGHT_SHADOWS > 0 || NUM_POINT_LIGHT_SHADOWS > 0 ) ) || ( NUM_SPOT_LIGHT_COORDS > 0 )
	vec3 shadowWorldNormal = inverseTransformDirection( transformedNormal, viewMatrix );
	vec4 shadowWorldPosition;
#endif
#if defined( USE_SHADOWMAP )
	#if NUM_DIR_LIGHT_SHADOWS > 0
		#pragma unroll_loop_start
		for ( int i = 0; i < NUM_DIR_LIGHT_SHADOWS; i ++ ) {
			shadowWorldPosition = worldPosition + vec4( shadowWorldNormal * directionalLightShadows[ i ].shadowNormalBias, 0 );
			vDirectionalShadowCoord[ i ] = directionalShadowMatrix[ i ] * shadowWorldPosition;
		}
		#pragma unroll_loop_end
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
		#pragma unroll_loop_start
		for ( int i = 0; i < NUM_POINT_LIGHT_SHADOWS; i ++ ) {
			shadowWorldPosition = worldPosition + vec4( shadowWorldNormal * pointLightShadows[ i ].shadowNormalBias, 0 );
			vPointShadowCoord[ i ] = pointShadowMatrix[ i ] * shadowWorldPosition;
		}
		#pragma unroll_loop_end
	#endif
#endif
#if NUM_SPOT_LIGHT_COORDS > 0
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_SPOT_LIGHT_COORDS; i ++ ) {
		shadowWorldPosition = worldPosition;
		#if ( defined( USE_SHADOWMAP ) && UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS )
			shadowWorldPosition.xyz += shadowWorldNormal * spotLightShadows[ i ].shadowNormalBias;
		#endif
		vSpotLightCoord[ i ] = spotLightMatrix[ i ] * shadowWorldPosition;
	}
	#pragma unroll_loop_end
#endif`,$s=`float getShadowMask() {
	float shadow = 1.0;
	#ifdef USE_SHADOWMAP
	#if NUM_DIR_LIGHT_SHADOWS > 0
	DirectionalLightShadow directionalLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_DIR_LIGHT_SHADOWS; i ++ ) {
		directionalLight = directionalLightShadows[ i ];
		shadow *= receiveShadow ? getShadow( directionalShadowMap[ i ], directionalLight.shadowMapSize, directionalLight.shadowIntensity, directionalLight.shadowBias, directionalLight.shadowRadius, vDirectionalShadowCoord[ i ] ) : 1.0;
	}
	#pragma unroll_loop_end
	#endif
	#if NUM_SPOT_LIGHT_SHADOWS > 0
	SpotLightShadow spotLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_SPOT_LIGHT_SHADOWS; i ++ ) {
		spotLight = spotLightShadows[ i ];
		shadow *= receiveShadow ? getShadow( spotShadowMap[ i ], spotLight.shadowMapSize, spotLight.shadowIntensity, spotLight.shadowBias, spotLight.shadowRadius, vSpotLightCoord[ i ] ) : 1.0;
	}
	#pragma unroll_loop_end
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
	PointLightShadow pointLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_POINT_LIGHT_SHADOWS; i ++ ) {
		pointLight = pointLightShadows[ i ];
		shadow *= receiveShadow ? getPointShadow( pointShadowMap[ i ], pointLight.shadowMapSize, pointLight.shadowIntensity, pointLight.shadowBias, pointLight.shadowRadius, vPointShadowCoord[ i ], pointLight.shadowCameraNear, pointLight.shadowCameraFar ) : 1.0;
	}
	#pragma unroll_loop_end
	#endif
	#endif
	return shadow;
}`,Zs=`#ifdef USE_SKINNING
	mat4 boneMatX = getBoneMatrix( skinIndex.x );
	mat4 boneMatY = getBoneMatrix( skinIndex.y );
	mat4 boneMatZ = getBoneMatrix( skinIndex.z );
	mat4 boneMatW = getBoneMatrix( skinIndex.w );
#endif`,Qs=`#ifdef USE_SKINNING
	uniform mat4 bindMatrix;
	uniform mat4 bindMatrixInverse;
	uniform highp sampler2D boneTexture;
	mat4 getBoneMatrix( const in float i ) {
		int size = textureSize( boneTexture, 0 ).x;
		int j = int( i ) * 4;
		int x = j % size;
		int y = j / size;
		vec4 v1 = texelFetch( boneTexture, ivec2( x, y ), 0 );
		vec4 v2 = texelFetch( boneTexture, ivec2( x + 1, y ), 0 );
		vec4 v3 = texelFetch( boneTexture, ivec2( x + 2, y ), 0 );
		vec4 v4 = texelFetch( boneTexture, ivec2( x + 3, y ), 0 );
		return mat4( v1, v2, v3, v4 );
	}
#endif`,Js=`#ifdef USE_SKINNING
	vec4 skinVertex = bindMatrix * vec4( transformed, 1.0 );
	vec4 skinned = vec4( 0.0 );
	skinned += boneMatX * skinVertex * skinWeight.x;
	skinned += boneMatY * skinVertex * skinWeight.y;
	skinned += boneMatZ * skinVertex * skinWeight.z;
	skinned += boneMatW * skinVertex * skinWeight.w;
	transformed = ( bindMatrixInverse * skinned ).xyz;
#endif`,js=`#ifdef USE_SKINNING
	mat4 skinMatrix = mat4( 0.0 );
	skinMatrix += skinWeight.x * boneMatX;
	skinMatrix += skinWeight.y * boneMatY;
	skinMatrix += skinWeight.z * boneMatZ;
	skinMatrix += skinWeight.w * boneMatW;
	skinMatrix = bindMatrixInverse * skinMatrix * bindMatrix;
	objectNormal = vec4( skinMatrix * vec4( objectNormal, 0.0 ) ).xyz;
	#ifdef USE_TANGENT
		objectTangent = vec4( skinMatrix * vec4( objectTangent, 0.0 ) ).xyz;
	#endif
#endif`,ec=`float specularStrength;
#ifdef USE_SPECULARMAP
	vec4 texelSpecular = texture2D( specularMap, vSpecularMapUv );
	specularStrength = texelSpecular.r;
#else
	specularStrength = 1.0;
#endif`,tc=`#ifdef USE_SPECULARMAP
	uniform sampler2D specularMap;
#endif`,nc=`#if defined( TONE_MAPPING )
	gl_FragColor.rgb = toneMapping( gl_FragColor.rgb );
#endif`,ic=`#ifndef saturate
#define saturate( a ) clamp( a, 0.0, 1.0 )
#endif
uniform float toneMappingExposure;
vec3 LinearToneMapping( vec3 color ) {
	return saturate( toneMappingExposure * color );
}
vec3 ReinhardToneMapping( vec3 color ) {
	color *= toneMappingExposure;
	return saturate( color / ( vec3( 1.0 ) + color ) );
}
vec3 CineonToneMapping( vec3 color ) {
	color *= toneMappingExposure;
	color = max( vec3( 0.0 ), color - 0.004 );
	return pow( ( color * ( 6.2 * color + 0.5 ) ) / ( color * ( 6.2 * color + 1.7 ) + 0.06 ), vec3( 2.2 ) );
}
vec3 RRTAndODTFit( vec3 v ) {
	vec3 a = v * ( v + 0.0245786 ) - 0.000090537;
	vec3 b = v * ( 0.983729 * v + 0.4329510 ) + 0.238081;
	return a / b;
}
vec3 ACESFilmicToneMapping( vec3 color ) {
	const mat3 ACESInputMat = mat3(
		vec3( 0.59719, 0.07600, 0.02840 ),		vec3( 0.35458, 0.90834, 0.13383 ),
		vec3( 0.04823, 0.01566, 0.83777 )
	);
	const mat3 ACESOutputMat = mat3(
		vec3(  1.60475, -0.10208, -0.00327 ),		vec3( -0.53108,  1.10813, -0.07276 ),
		vec3( -0.07367, -0.00605,  1.07602 )
	);
	color *= toneMappingExposure / 0.6;
	color = ACESInputMat * color;
	color = RRTAndODTFit( color );
	color = ACESOutputMat * color;
	return saturate( color );
}
const mat3 LINEAR_REC2020_TO_LINEAR_SRGB = mat3(
	vec3( 1.6605, - 0.1246, - 0.0182 ),
	vec3( - 0.5876, 1.1329, - 0.1006 ),
	vec3( - 0.0728, - 0.0083, 1.1187 )
);
const mat3 LINEAR_SRGB_TO_LINEAR_REC2020 = mat3(
	vec3( 0.6274, 0.0691, 0.0164 ),
	vec3( 0.3293, 0.9195, 0.0880 ),
	vec3( 0.0433, 0.0113, 0.8956 )
);
vec3 agxDefaultContrastApprox( vec3 x ) {
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return + 15.5 * x4 * x2
		- 40.14 * x4 * x
		+ 31.96 * x4
		- 6.868 * x2 * x
		+ 0.4298 * x2
		+ 0.1191 * x
		- 0.00232;
}
vec3 AgXToneMapping( vec3 color ) {
	const mat3 AgXInsetMatrix = mat3(
		vec3( 0.856627153315983, 0.137318972929847, 0.11189821299995 ),
		vec3( 0.0951212405381588, 0.761241990602591, 0.0767994186031903 ),
		vec3( 0.0482516061458583, 0.101439036467562, 0.811302368396859 )
	);
	const mat3 AgXOutsetMatrix = mat3(
		vec3( 1.1271005818144368, - 0.1413297634984383, - 0.14132976349843826 ),
		vec3( - 0.11060664309660323, 1.157823702216272, - 0.11060664309660294 ),
		vec3( - 0.016493938717834573, - 0.016493938717834257, 1.2519364065950405 )
	);
	const float AgxMinEv = - 12.47393;	const float AgxMaxEv = 4.026069;
	color *= toneMappingExposure;
	color = LINEAR_SRGB_TO_LINEAR_REC2020 * color;
	color = AgXInsetMatrix * color;
	color = max( color, 1e-10 );	color = log2( color );
	color = ( color - AgxMinEv ) / ( AgxMaxEv - AgxMinEv );
	color = clamp( color, 0.0, 1.0 );
	color = agxDefaultContrastApprox( color );
	color = AgXOutsetMatrix * color;
	color = pow( max( vec3( 0.0 ), color ), vec3( 2.2 ) );
	color = LINEAR_REC2020_TO_LINEAR_SRGB * color;
	color = clamp( color, 0.0, 1.0 );
	return color;
}
vec3 NeutralToneMapping( vec3 color ) {
	const float StartCompression = 0.8 - 0.04;
	const float Desaturation = 0.15;
	color *= toneMappingExposure;
	float x = min( color.r, min( color.g, color.b ) );
	float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
	color -= offset;
	float peak = max( color.r, max( color.g, color.b ) );
	if ( peak < StartCompression ) return color;
	float d = 1. - StartCompression;
	float newPeak = 1. - d * d / ( peak + d - StartCompression );
	color *= newPeak / peak;
	float g = 1. - 1. / ( Desaturation * ( peak - newPeak ) + 1. );
	return mix( color, vec3( newPeak ), g );
}
vec3 CustomToneMapping( vec3 color ) { return color; }`,rc=`#ifdef USE_TRANSMISSION
	material.transmission = transmission;
	material.transmissionAlpha = 1.0;
	material.thickness = thickness;
	material.attenuationDistance = attenuationDistance;
	material.attenuationColor = attenuationColor;
	#ifdef USE_TRANSMISSIONMAP
		material.transmission *= texture2D( transmissionMap, vTransmissionMapUv ).r;
	#endif
	#ifdef USE_THICKNESSMAP
		material.thickness *= texture2D( thicknessMap, vThicknessMapUv ).g;
	#endif
	vec3 pos = vWorldPosition;
	vec3 v = normalize( cameraPosition - pos );
	vec3 n = inverseTransformDirection( normal, viewMatrix );
	vec4 transmitted = getIBLVolumeRefraction(
		n, v, material.roughness, material.diffuseColor, material.specularColor, material.specularF90,
		pos, modelMatrix, viewMatrix, projectionMatrix, material.dispersion, material.ior, material.thickness,
		material.attenuationColor, material.attenuationDistance );
	material.transmissionAlpha = mix( material.transmissionAlpha, transmitted.a, material.transmission );
	totalDiffuse = mix( totalDiffuse, transmitted.rgb, material.transmission );
#endif`,ac=`#ifdef USE_TRANSMISSION
	uniform float transmission;
	uniform float thickness;
	uniform float attenuationDistance;
	uniform vec3 attenuationColor;
	#ifdef USE_TRANSMISSIONMAP
		uniform sampler2D transmissionMap;
	#endif
	#ifdef USE_THICKNESSMAP
		uniform sampler2D thicknessMap;
	#endif
	uniform vec2 transmissionSamplerSize;
	uniform sampler2D transmissionSamplerMap;
	uniform mat4 modelMatrix;
	uniform mat4 projectionMatrix;
	varying vec3 vWorldPosition;
	float w0( float a ) {
		return ( 1.0 / 6.0 ) * ( a * ( a * ( - a + 3.0 ) - 3.0 ) + 1.0 );
	}
	float w1( float a ) {
		return ( 1.0 / 6.0 ) * ( a *  a * ( 3.0 * a - 6.0 ) + 4.0 );
	}
	float w2( float a ){
		return ( 1.0 / 6.0 ) * ( a * ( a * ( - 3.0 * a + 3.0 ) + 3.0 ) + 1.0 );
	}
	float w3( float a ) {
		return ( 1.0 / 6.0 ) * ( a * a * a );
	}
	float g0( float a ) {
		return w0( a ) + w1( a );
	}
	float g1( float a ) {
		return w2( a ) + w3( a );
	}
	float h0( float a ) {
		return - 1.0 + w1( a ) / ( w0( a ) + w1( a ) );
	}
	float h1( float a ) {
		return 1.0 + w3( a ) / ( w2( a ) + w3( a ) );
	}
	vec4 bicubic( sampler2D tex, vec2 uv, vec4 texelSize, float lod ) {
		uv = uv * texelSize.zw + 0.5;
		vec2 iuv = floor( uv );
		vec2 fuv = fract( uv );
		float g0x = g0( fuv.x );
		float g1x = g1( fuv.x );
		float h0x = h0( fuv.x );
		float h1x = h1( fuv.x );
		float h0y = h0( fuv.y );
		float h1y = h1( fuv.y );
		vec2 p0 = ( vec2( iuv.x + h0x, iuv.y + h0y ) - 0.5 ) * texelSize.xy;
		vec2 p1 = ( vec2( iuv.x + h1x, iuv.y + h0y ) - 0.5 ) * texelSize.xy;
		vec2 p2 = ( vec2( iuv.x + h0x, iuv.y + h1y ) - 0.5 ) * texelSize.xy;
		vec2 p3 = ( vec2( iuv.x + h1x, iuv.y + h1y ) - 0.5 ) * texelSize.xy;
		return g0( fuv.y ) * ( g0x * textureLod( tex, p0, lod ) + g1x * textureLod( tex, p1, lod ) ) +
			g1( fuv.y ) * ( g0x * textureLod( tex, p2, lod ) + g1x * textureLod( tex, p3, lod ) );
	}
	vec4 textureBicubic( sampler2D sampler, vec2 uv, float lod ) {
		vec2 fLodSize = vec2( textureSize( sampler, int( lod ) ) );
		vec2 cLodSize = vec2( textureSize( sampler, int( lod + 1.0 ) ) );
		vec2 fLodSizeInv = 1.0 / fLodSize;
		vec2 cLodSizeInv = 1.0 / cLodSize;
		vec4 fSample = bicubic( sampler, uv, vec4( fLodSizeInv, fLodSize ), floor( lod ) );
		vec4 cSample = bicubic( sampler, uv, vec4( cLodSizeInv, cLodSize ), ceil( lod ) );
		return mix( fSample, cSample, fract( lod ) );
	}
	vec3 getVolumeTransmissionRay( const in vec3 n, const in vec3 v, const in float thickness, const in float ior, const in mat4 modelMatrix ) {
		vec3 refractionVector = refract( - v, normalize( n ), 1.0 / ior );
		vec3 modelScale;
		modelScale.x = length( vec3( modelMatrix[ 0 ].xyz ) );
		modelScale.y = length( vec3( modelMatrix[ 1 ].xyz ) );
		modelScale.z = length( vec3( modelMatrix[ 2 ].xyz ) );
		return normalize( refractionVector ) * thickness * modelScale;
	}
	float applyIorToRoughness( const in float roughness, const in float ior ) {
		return roughness * clamp( ior * 2.0 - 2.0, 0.0, 1.0 );
	}
	vec4 getTransmissionSample( const in vec2 fragCoord, const in float roughness, const in float ior ) {
		float lod = log2( transmissionSamplerSize.x ) * applyIorToRoughness( roughness, ior );
		return textureBicubic( transmissionSamplerMap, fragCoord.xy, lod );
	}
	vec3 volumeAttenuation( const in float transmissionDistance, const in vec3 attenuationColor, const in float attenuationDistance ) {
		if ( isinf( attenuationDistance ) ) {
			return vec3( 1.0 );
		} else {
			vec3 attenuationCoefficient = -log( attenuationColor ) / attenuationDistance;
			vec3 transmittance = exp( - attenuationCoefficient * transmissionDistance );			return transmittance;
		}
	}
	vec4 getIBLVolumeRefraction( const in vec3 n, const in vec3 v, const in float roughness, const in vec3 diffuseColor,
		const in vec3 specularColor, const in float specularF90, const in vec3 position, const in mat4 modelMatrix,
		const in mat4 viewMatrix, const in mat4 projMatrix, const in float dispersion, const in float ior, const in float thickness,
		const in vec3 attenuationColor, const in float attenuationDistance ) {
		vec4 transmittedLight;
		vec3 transmittance;
		#ifdef USE_DISPERSION
			float halfSpread = ( ior - 1.0 ) * 0.025 * dispersion;
			vec3 iors = vec3( ior - halfSpread, ior, ior + halfSpread );
			for ( int i = 0; i < 3; i ++ ) {
				vec3 transmissionRay = getVolumeTransmissionRay( n, v, thickness, iors[ i ], modelMatrix );
				vec3 refractedRayExit = position + transmissionRay;
				vec4 ndcPos = projMatrix * viewMatrix * vec4( refractedRayExit, 1.0 );
				vec2 refractionCoords = ndcPos.xy / ndcPos.w;
				refractionCoords += 1.0;
				refractionCoords /= 2.0;
				vec4 transmissionSample = getTransmissionSample( refractionCoords, roughness, iors[ i ] );
				transmittedLight[ i ] = transmissionSample[ i ];
				transmittedLight.a += transmissionSample.a;
				transmittance[ i ] = diffuseColor[ i ] * volumeAttenuation( length( transmissionRay ), attenuationColor, attenuationDistance )[ i ];
			}
			transmittedLight.a /= 3.0;
		#else
			vec3 transmissionRay = getVolumeTransmissionRay( n, v, thickness, ior, modelMatrix );
			vec3 refractedRayExit = position + transmissionRay;
			vec4 ndcPos = projMatrix * viewMatrix * vec4( refractedRayExit, 1.0 );
			vec2 refractionCoords = ndcPos.xy / ndcPos.w;
			refractionCoords += 1.0;
			refractionCoords /= 2.0;
			transmittedLight = getTransmissionSample( refractionCoords, roughness, ior );
			transmittance = diffuseColor * volumeAttenuation( length( transmissionRay ), attenuationColor, attenuationDistance );
		#endif
		vec3 attenuatedColor = transmittance * transmittedLight.rgb;
		vec3 F = EnvironmentBRDF( n, v, specularColor, specularF90, roughness );
		float transmittanceFactor = ( transmittance.r + transmittance.g + transmittance.b ) / 3.0;
		return vec4( ( 1.0 - F ) * attenuatedColor, 1.0 - ( 1.0 - transmittedLight.a ) * transmittanceFactor );
	}
#endif`,oc=`#if defined( USE_UV ) || defined( USE_ANISOTROPY )
	varying vec2 vUv;
#endif
#ifdef USE_MAP
	varying vec2 vMapUv;
#endif
#ifdef USE_ALPHAMAP
	varying vec2 vAlphaMapUv;
#endif
#ifdef USE_LIGHTMAP
	varying vec2 vLightMapUv;
#endif
#ifdef USE_AOMAP
	varying vec2 vAoMapUv;
#endif
#ifdef USE_BUMPMAP
	varying vec2 vBumpMapUv;
#endif
#ifdef USE_NORMALMAP
	varying vec2 vNormalMapUv;
#endif
#ifdef USE_EMISSIVEMAP
	varying vec2 vEmissiveMapUv;
#endif
#ifdef USE_METALNESSMAP
	varying vec2 vMetalnessMapUv;
#endif
#ifdef USE_ROUGHNESSMAP
	varying vec2 vRoughnessMapUv;
#endif
#ifdef USE_ANISOTROPYMAP
	varying vec2 vAnisotropyMapUv;
#endif
#ifdef USE_CLEARCOATMAP
	varying vec2 vClearcoatMapUv;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	varying vec2 vClearcoatNormalMapUv;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	varying vec2 vClearcoatRoughnessMapUv;
#endif
#ifdef USE_IRIDESCENCEMAP
	varying vec2 vIridescenceMapUv;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	varying vec2 vIridescenceThicknessMapUv;
#endif
#ifdef USE_SHEEN_COLORMAP
	varying vec2 vSheenColorMapUv;
#endif
#ifdef USE_SHEEN_ROUGHNESSMAP
	varying vec2 vSheenRoughnessMapUv;
#endif
#ifdef USE_SPECULARMAP
	varying vec2 vSpecularMapUv;
#endif
#ifdef USE_SPECULAR_COLORMAP
	varying vec2 vSpecularColorMapUv;
#endif
#ifdef USE_SPECULAR_INTENSITYMAP
	varying vec2 vSpecularIntensityMapUv;
#endif
#ifdef USE_TRANSMISSIONMAP
	uniform mat3 transmissionMapTransform;
	varying vec2 vTransmissionMapUv;
#endif
#ifdef USE_THICKNESSMAP
	uniform mat3 thicknessMapTransform;
	varying vec2 vThicknessMapUv;
#endif`,sc=`#if defined( USE_UV ) || defined( USE_ANISOTROPY )
	varying vec2 vUv;
#endif
#ifdef USE_MAP
	uniform mat3 mapTransform;
	varying vec2 vMapUv;
#endif
#ifdef USE_ALPHAMAP
	uniform mat3 alphaMapTransform;
	varying vec2 vAlphaMapUv;
#endif
#ifdef USE_LIGHTMAP
	uniform mat3 lightMapTransform;
	varying vec2 vLightMapUv;
#endif
#ifdef USE_AOMAP
	uniform mat3 aoMapTransform;
	varying vec2 vAoMapUv;
#endif
#ifdef USE_BUMPMAP
	uniform mat3 bumpMapTransform;
	varying vec2 vBumpMapUv;
#endif
#ifdef USE_NORMALMAP
	uniform mat3 normalMapTransform;
	varying vec2 vNormalMapUv;
#endif
#ifdef USE_DISPLACEMENTMAP
	uniform mat3 displacementMapTransform;
	varying vec2 vDisplacementMapUv;
#endif
#ifdef USE_EMISSIVEMAP
	uniform mat3 emissiveMapTransform;
	varying vec2 vEmissiveMapUv;
#endif
#ifdef USE_METALNESSMAP
	uniform mat3 metalnessMapTransform;
	varying vec2 vMetalnessMapUv;
#endif
#ifdef USE_ROUGHNESSMAP
	uniform mat3 roughnessMapTransform;
	varying vec2 vRoughnessMapUv;
#endif
#ifdef USE_ANISOTROPYMAP
	uniform mat3 anisotropyMapTransform;
	varying vec2 vAnisotropyMapUv;
#endif
#ifdef USE_CLEARCOATMAP
	uniform mat3 clearcoatMapTransform;
	varying vec2 vClearcoatMapUv;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	uniform mat3 clearcoatNormalMapTransform;
	varying vec2 vClearcoatNormalMapUv;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	uniform mat3 clearcoatRoughnessMapTransform;
	varying vec2 vClearcoatRoughnessMapUv;
#endif
#ifdef USE_SHEEN_COLORMAP
	uniform mat3 sheenColorMapTransform;
	varying vec2 vSheenColorMapUv;
#endif
#ifdef USE_SHEEN_ROUGHNESSMAP
	uniform mat3 sheenRoughnessMapTransform;
	varying vec2 vSheenRoughnessMapUv;
#endif
#ifdef USE_IRIDESCENCEMAP
	uniform mat3 iridescenceMapTransform;
	varying vec2 vIridescenceMapUv;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	uniform mat3 iridescenceThicknessMapTransform;
	varying vec2 vIridescenceThicknessMapUv;
#endif
#ifdef USE_SPECULARMAP
	uniform mat3 specularMapTransform;
	varying vec2 vSpecularMapUv;
#endif
#ifdef USE_SPECULAR_COLORMAP
	uniform mat3 specularColorMapTransform;
	varying vec2 vSpecularColorMapUv;
#endif
#ifdef USE_SPECULAR_INTENSITYMAP
	uniform mat3 specularIntensityMapTransform;
	varying vec2 vSpecularIntensityMapUv;
#endif
#ifdef USE_TRANSMISSIONMAP
	uniform mat3 transmissionMapTransform;
	varying vec2 vTransmissionMapUv;
#endif
#ifdef USE_THICKNESSMAP
	uniform mat3 thicknessMapTransform;
	varying vec2 vThicknessMapUv;
#endif`,cc=`#if defined( USE_UV ) || defined( USE_ANISOTROPY )
	vUv = vec3( uv, 1 ).xy;
#endif
#ifdef USE_MAP
	vMapUv = ( mapTransform * vec3( MAP_UV, 1 ) ).xy;
#endif
#ifdef USE_ALPHAMAP
	vAlphaMapUv = ( alphaMapTransform * vec3( ALPHAMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_LIGHTMAP
	vLightMapUv = ( lightMapTransform * vec3( LIGHTMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_AOMAP
	vAoMapUv = ( aoMapTransform * vec3( AOMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_BUMPMAP
	vBumpMapUv = ( bumpMapTransform * vec3( BUMPMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_NORMALMAP
	vNormalMapUv = ( normalMapTransform * vec3( NORMALMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_DISPLACEMENTMAP
	vDisplacementMapUv = ( displacementMapTransform * vec3( DISPLACEMENTMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_EMISSIVEMAP
	vEmissiveMapUv = ( emissiveMapTransform * vec3( EMISSIVEMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_METALNESSMAP
	vMetalnessMapUv = ( metalnessMapTransform * vec3( METALNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_ROUGHNESSMAP
	vRoughnessMapUv = ( roughnessMapTransform * vec3( ROUGHNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_ANISOTROPYMAP
	vAnisotropyMapUv = ( anisotropyMapTransform * vec3( ANISOTROPYMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_CLEARCOATMAP
	vClearcoatMapUv = ( clearcoatMapTransform * vec3( CLEARCOATMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	vClearcoatNormalMapUv = ( clearcoatNormalMapTransform * vec3( CLEARCOAT_NORMALMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	vClearcoatRoughnessMapUv = ( clearcoatRoughnessMapTransform * vec3( CLEARCOAT_ROUGHNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_IRIDESCENCEMAP
	vIridescenceMapUv = ( iridescenceMapTransform * vec3( IRIDESCENCEMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	vIridescenceThicknessMapUv = ( iridescenceThicknessMapTransform * vec3( IRIDESCENCE_THICKNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SHEEN_COLORMAP
	vSheenColorMapUv = ( sheenColorMapTransform * vec3( SHEEN_COLORMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SHEEN_ROUGHNESSMAP
	vSheenRoughnessMapUv = ( sheenRoughnessMapTransform * vec3( SHEEN_ROUGHNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SPECULARMAP
	vSpecularMapUv = ( specularMapTransform * vec3( SPECULARMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SPECULAR_COLORMAP
	vSpecularColorMapUv = ( specularColorMapTransform * vec3( SPECULAR_COLORMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SPECULAR_INTENSITYMAP
	vSpecularIntensityMapUv = ( specularIntensityMapTransform * vec3( SPECULAR_INTENSITYMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_TRANSMISSIONMAP
	vTransmissionMapUv = ( transmissionMapTransform * vec3( TRANSMISSIONMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_THICKNESSMAP
	vThicknessMapUv = ( thicknessMapTransform * vec3( THICKNESSMAP_UV, 1 ) ).xy;
#endif`,lc=`#if defined( USE_ENVMAP ) || defined( DISTANCE ) || defined ( USE_SHADOWMAP ) || defined ( USE_TRANSMISSION ) || NUM_SPOT_LIGHT_COORDS > 0
	vec4 worldPosition = vec4( transformed, 1.0 );
	#ifdef USE_BATCHING
		worldPosition = batchingMatrix * worldPosition;
	#endif
	#ifdef USE_INSTANCING
		worldPosition = instanceMatrix * worldPosition;
	#endif
	worldPosition = modelMatrix * worldPosition;
#endif`,fc=`varying vec2 vUv;
uniform mat3 uvTransform;
void main() {
	vUv = ( uvTransform * vec3( uv, 1 ) ).xy;
	gl_Position = vec4( position.xy, 1.0, 1.0 );
}`,dc=`uniform sampler2D t2D;
uniform float backgroundIntensity;
varying vec2 vUv;
void main() {
	vec4 texColor = texture2D( t2D, vUv );
	#ifdef DECODE_VIDEO_TEXTURE
		texColor = vec4( mix( pow( texColor.rgb * 0.9478672986 + vec3( 0.0521327014 ), vec3( 2.4 ) ), texColor.rgb * 0.0773993808, vec3( lessThanEqual( texColor.rgb, vec3( 0.04045 ) ) ) ), texColor.w );
	#endif
	texColor.rgb *= backgroundIntensity;
	gl_FragColor = texColor;
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,uc=`varying vec3 vWorldDirection;
#include <common>
void main() {
	vWorldDirection = transformDirection( position, modelMatrix );
	#include <begin_vertex>
	#include <project_vertex>
	gl_Position.z = gl_Position.w;
}`,pc=`#ifdef ENVMAP_TYPE_CUBE
	uniform samplerCube envMap;
#elif defined( ENVMAP_TYPE_CUBE_UV )
	uniform sampler2D envMap;
#endif
uniform float flipEnvMap;
uniform float backgroundBlurriness;
uniform float backgroundIntensity;
uniform mat3 backgroundRotation;
varying vec3 vWorldDirection;
#include <cube_uv_reflection_fragment>
void main() {
	#ifdef ENVMAP_TYPE_CUBE
		vec4 texColor = textureCube( envMap, backgroundRotation * vec3( flipEnvMap * vWorldDirection.x, vWorldDirection.yz ) );
	#elif defined( ENVMAP_TYPE_CUBE_UV )
		vec4 texColor = textureCubeUV( envMap, backgroundRotation * vWorldDirection, backgroundBlurriness );
	#else
		vec4 texColor = vec4( 0.0, 0.0, 0.0, 1.0 );
	#endif
	texColor.rgb *= backgroundIntensity;
	gl_FragColor = texColor;
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,hc=`varying vec3 vWorldDirection;
#include <common>
void main() {
	vWorldDirection = transformDirection( position, modelMatrix );
	#include <begin_vertex>
	#include <project_vertex>
	gl_Position.z = gl_Position.w;
}`,mc=`uniform samplerCube tCube;
uniform float tFlip;
uniform float opacity;
varying vec3 vWorldDirection;
void main() {
	vec4 texColor = textureCube( tCube, vec3( tFlip * vWorldDirection.x, vWorldDirection.yz ) );
	gl_FragColor = texColor;
	gl_FragColor.a *= opacity;
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,_c=`#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
varying vec2 vHighPrecisionZW;
void main() {
	#include <uv_vertex>
	#include <batching_vertex>
	#include <skinbase_vertex>
	#include <morphinstance_vertex>
	#ifdef USE_DISPLACEMENTMAP
		#include <beginnormal_vertex>
		#include <morphnormal_vertex>
		#include <skinnormal_vertex>
	#endif
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vHighPrecisionZW = gl_Position.zw;
}`,vc=`#if DEPTH_PACKING == 3200
	uniform float opacity;
#endif
#include <common>
#include <packing>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
varying vec2 vHighPrecisionZW;
void main() {
	vec4 diffuseColor = vec4( 1.0 );
	#include <clipping_planes_fragment>
	#if DEPTH_PACKING == 3200
		diffuseColor.a = opacity;
	#endif
	#include <map_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <logdepthbuf_fragment>
	float fragCoordZ = 0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5;
	#if DEPTH_PACKING == 3200
		gl_FragColor = vec4( vec3( 1.0 - fragCoordZ ), opacity );
	#elif DEPTH_PACKING == 3201
		gl_FragColor = packDepthToRGBA( fragCoordZ );
	#elif DEPTH_PACKING == 3202
		gl_FragColor = vec4( packDepthToRGB( fragCoordZ ), 1.0 );
	#elif DEPTH_PACKING == 3203
		gl_FragColor = vec4( packDepthToRG( fragCoordZ ), 0.0, 1.0 );
	#endif
}`,gc=`#define DISTANCE
varying vec3 vWorldPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <batching_vertex>
	#include <skinbase_vertex>
	#include <morphinstance_vertex>
	#ifdef USE_DISPLACEMENTMAP
		#include <beginnormal_vertex>
		#include <morphnormal_vertex>
		#include <skinnormal_vertex>
	#endif
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <worldpos_vertex>
	#include <clipping_planes_vertex>
	vWorldPosition = worldPosition.xyz;
}`,Sc=`#define DISTANCE
uniform vec3 referencePosition;
uniform float nearDistance;
uniform float farDistance;
varying vec3 vWorldPosition;
#include <common>
#include <packing>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <clipping_planes_pars_fragment>
void main () {
	vec4 diffuseColor = vec4( 1.0 );
	#include <clipping_planes_fragment>
	#include <map_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	float dist = length( vWorldPosition - referencePosition );
	dist = ( dist - nearDistance ) / ( farDistance - nearDistance );
	dist = saturate( dist );
	gl_FragColor = packDepthToRGBA( dist );
}`,Ec=`varying vec3 vWorldDirection;
#include <common>
void main() {
	vWorldDirection = transformDirection( position, modelMatrix );
	#include <begin_vertex>
	#include <project_vertex>
}`,Mc=`uniform sampler2D tEquirect;
varying vec3 vWorldDirection;
#include <common>
void main() {
	vec3 direction = normalize( vWorldDirection );
	vec2 sampleUV = equirectUv( direction );
	gl_FragColor = texture2D( tEquirect, sampleUV );
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,Tc=`uniform float scale;
attribute float lineDistance;
varying float vLineDistance;
#include <common>
#include <uv_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	vLineDistance = scale * lineDistance;
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <fog_vertex>
}`,xc=`uniform vec3 diffuse;
uniform float opacity;
uniform float dashSize;
uniform float totalSize;
varying float vLineDistance;
#include <common>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <fog_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	if ( mod( vLineDistance, totalSize ) > dashSize ) {
		discard;
	}
	vec3 outgoingLight = vec3( 0.0 );
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	outgoingLight = diffuseColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
}`,Ac=`#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <envmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#if defined ( USE_ENVMAP ) || defined ( USE_SKINNING )
		#include <beginnormal_vertex>
		#include <morphnormal_vertex>
		#include <skinbase_vertex>
		#include <skinnormal_vertex>
		#include <defaultnormal_vertex>
	#endif
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <worldpos_vertex>
	#include <envmap_vertex>
	#include <fog_vertex>
}`,Rc=`uniform vec3 diffuse;
uniform float opacity;
#ifndef FLAT_SHADED
	varying vec3 vNormal;
#endif
#include <common>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_pars_fragment>
#include <fog_pars_fragment>
#include <specularmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <specularmap_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	#ifdef USE_LIGHTMAP
		vec4 lightMapTexel = texture2D( lightMap, vLightMapUv );
		reflectedLight.indirectDiffuse += lightMapTexel.rgb * lightMapIntensity * RECIPROCAL_PI;
	#else
		reflectedLight.indirectDiffuse += vec3( 1.0 );
	#endif
	#include <aomap_fragment>
	reflectedLight.indirectDiffuse *= diffuseColor.rgb;
	vec3 outgoingLight = reflectedLight.indirectDiffuse;
	#include <envmap_fragment>
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,Cc=`#define LAMBERT
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <envmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <envmap_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,bc=`#define LAMBERT
uniform vec3 diffuse;
uniform vec3 emissive;
uniform float opacity;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_pars_fragment>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_lambert_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <specularmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <specularmap_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_lambert_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + totalEmissiveRadiance;
	#include <envmap_fragment>
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,Pc=`#define MATCAP
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <color_pars_vertex>
#include <displacementmap_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <fog_vertex>
	vViewPosition = - mvPosition.xyz;
}`,Lc=`#define MATCAP
uniform vec3 diffuse;
uniform float opacity;
uniform sampler2D matcap;
varying vec3 vViewPosition;
#include <common>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <fog_pars_fragment>
#include <normal_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	vec3 viewDir = normalize( vViewPosition );
	vec3 x = normalize( vec3( viewDir.z, 0.0, - viewDir.x ) );
	vec3 y = cross( viewDir, x );
	vec2 uv = vec2( dot( x, normal ), dot( y, normal ) ) * 0.495 + 0.5;
	#ifdef USE_MATCAP
		vec4 matcapColor = texture2D( matcap, uv );
	#else
		vec4 matcapColor = vec4( vec3( mix( 0.2, 0.8, uv.y ) ), 1.0 );
	#endif
	vec3 outgoingLight = diffuseColor.rgb * matcapColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,Uc=`#define NORMAL
#if defined( FLAT_SHADED ) || defined( USE_BUMPMAP ) || defined( USE_NORMALMAP_TANGENTSPACE )
	varying vec3 vViewPosition;
#endif
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphinstance_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
#if defined( FLAT_SHADED ) || defined( USE_BUMPMAP ) || defined( USE_NORMALMAP_TANGENTSPACE )
	vViewPosition = - mvPosition.xyz;
#endif
}`,Dc=`#define NORMAL
uniform float opacity;
#if defined( FLAT_SHADED ) || defined( USE_BUMPMAP ) || defined( USE_NORMALMAP_TANGENTSPACE )
	varying vec3 vViewPosition;
#endif
#include <packing>
#include <uv_pars_fragment>
#include <normal_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( 0.0, 0.0, 0.0, opacity );
	#include <clipping_planes_fragment>
	#include <logdepthbuf_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	gl_FragColor = vec4( packNormalToRGB( normal ), diffuseColor.a );
	#ifdef OPAQUE
		gl_FragColor.a = 1.0;
	#endif
}`,wc=`#define PHONG
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <envmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphinstance_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <envmap_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,Ic=`#define PHONG
uniform vec3 diffuse;
uniform vec3 emissive;
uniform vec3 specular;
uniform float shininess;
uniform float opacity;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_pars_fragment>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_phong_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <specularmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <specularmap_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_phong_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + reflectedLight.directSpecular + reflectedLight.indirectSpecular + totalEmissiveRadiance;
	#include <envmap_fragment>
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,yc=`#define STANDARD
varying vec3 vViewPosition;
#ifdef USE_TRANSMISSION
	varying vec3 vWorldPosition;
#endif
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
#ifdef USE_TRANSMISSION
	vWorldPosition = worldPosition.xyz;
#endif
}`,Nc=`#define STANDARD
#ifdef PHYSICAL
	#define IOR
	#define USE_SPECULAR
#endif
uniform vec3 diffuse;
uniform vec3 emissive;
uniform float roughness;
uniform float metalness;
uniform float opacity;
#ifdef IOR
	uniform float ior;
#endif
#ifdef USE_SPECULAR
	uniform float specularIntensity;
	uniform vec3 specularColor;
	#ifdef USE_SPECULAR_COLORMAP
		uniform sampler2D specularColorMap;
	#endif
	#ifdef USE_SPECULAR_INTENSITYMAP
		uniform sampler2D specularIntensityMap;
	#endif
#endif
#ifdef USE_CLEARCOAT
	uniform float clearcoat;
	uniform float clearcoatRoughness;
#endif
#ifdef USE_DISPERSION
	uniform float dispersion;
#endif
#ifdef USE_IRIDESCENCE
	uniform float iridescence;
	uniform float iridescenceIOR;
	uniform float iridescenceThicknessMinimum;
	uniform float iridescenceThicknessMaximum;
#endif
#ifdef USE_SHEEN
	uniform vec3 sheenColor;
	uniform float sheenRoughness;
	#ifdef USE_SHEEN_COLORMAP
		uniform sampler2D sheenColorMap;
	#endif
	#ifdef USE_SHEEN_ROUGHNESSMAP
		uniform sampler2D sheenRoughnessMap;
	#endif
#endif
#ifdef USE_ANISOTROPY
	uniform vec2 anisotropyVector;
	#ifdef USE_ANISOTROPYMAP
		uniform sampler2D anisotropyMap;
	#endif
#endif
varying vec3 vViewPosition;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <iridescence_fragment>
#include <cube_uv_reflection_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_physical_pars_fragment>
#include <fog_pars_fragment>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_physical_pars_fragment>
#include <transmission_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <clearcoat_pars_fragment>
#include <iridescence_pars_fragment>
#include <roughnessmap_pars_fragment>
#include <metalnessmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <roughnessmap_fragment>
	#include <metalnessmap_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <clearcoat_normal_fragment_begin>
	#include <clearcoat_normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_physical_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 totalDiffuse = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse;
	vec3 totalSpecular = reflectedLight.directSpecular + reflectedLight.indirectSpecular;
	#include <transmission_fragment>
	vec3 outgoingLight = totalDiffuse + totalSpecular + totalEmissiveRadiance;
	#ifdef USE_SHEEN
		float sheenEnergyComp = 1.0 - 0.157 * max3( material.sheenColor );
		outgoingLight = outgoingLight * sheenEnergyComp + sheenSpecularDirect + sheenSpecularIndirect;
	#endif
	#ifdef USE_CLEARCOAT
		float dotNVcc = saturate( dot( geometryClearcoatNormal, geometryViewDir ) );
		vec3 Fcc = F_Schlick( material.clearcoatF0, material.clearcoatF90, dotNVcc );
		outgoingLight = outgoingLight * ( 1.0 - material.clearcoat * Fcc ) + ( clearcoatSpecularDirect + clearcoatSpecularIndirect ) * material.clearcoat;
	#endif
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,Oc=`#define TOON
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,Fc=`#define TOON
uniform vec3 diffuse;
uniform vec3 emissive;
uniform float opacity;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <gradientmap_pars_fragment>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_toon_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_toon_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + totalEmissiveRadiance;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,Bc=`uniform float size;
uniform float scale;
#include <common>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
#ifdef USE_POINTS_UV
	varying vec2 vUv;
	uniform mat3 uvTransform;
#endif
void main() {
	#ifdef USE_POINTS_UV
		vUv = ( uvTransform * vec3( uv, 1 ) ).xy;
	#endif
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <project_vertex>
	gl_PointSize = size;
	#ifdef USE_SIZEATTENUATION
		bool isPerspective = isPerspectiveMatrix( projectionMatrix );
		if ( isPerspective ) gl_PointSize *= ( scale / - mvPosition.z );
	#endif
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <worldpos_vertex>
	#include <fog_vertex>
}`,Gc=`uniform vec3 diffuse;
uniform float opacity;
#include <common>
#include <color_pars_fragment>
#include <map_particle_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <fog_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	vec3 outgoingLight = vec3( 0.0 );
	#include <logdepthbuf_fragment>
	#include <map_particle_fragment>
	#include <color_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	outgoingLight = diffuseColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
}`,Hc=`#include <common>
#include <batching_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <shadowmap_pars_vertex>
void main() {
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphinstance_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <worldpos_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,Vc=`uniform vec3 color;
uniform float opacity;
#include <common>
#include <packing>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <logdepthbuf_pars_fragment>
#include <shadowmap_pars_fragment>
#include <shadowmask_pars_fragment>
void main() {
	#include <logdepthbuf_fragment>
	gl_FragColor = vec4( color, opacity * ( 1.0 - getShadowMask() ) );
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
}`,kc=`uniform float rotation;
uniform vec2 center;
#include <common>
#include <uv_pars_vertex>
#include <fog_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	vec4 mvPosition = modelViewMatrix[ 3 ];
	vec2 scale = vec2( length( modelMatrix[ 0 ].xyz ), length( modelMatrix[ 1 ].xyz ) );
	#ifndef USE_SIZEATTENUATION
		bool isPerspective = isPerspectiveMatrix( projectionMatrix );
		if ( isPerspective ) scale *= - mvPosition.z;
	#endif
	vec2 alignedPosition = ( position.xy - ( center - vec2( 0.5 ) ) ) * scale;
	vec2 rotatedPosition;
	rotatedPosition.x = cos( rotation ) * alignedPosition.x - sin( rotation ) * alignedPosition.y;
	rotatedPosition.y = sin( rotation ) * alignedPosition.x + cos( rotation ) * alignedPosition.y;
	mvPosition.xy += rotatedPosition;
	gl_Position = projectionMatrix * mvPosition;
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <fog_vertex>
}`,zc=`uniform vec3 diffuse;
uniform float opacity;
#include <common>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <fog_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	vec3 outgoingLight = vec3( 0.0 );
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	outgoingLight = diffuseColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
}`,De={alphahash_fragment:fo,alphahash_pars_fragment:uo,alphamap_fragment:po,alphamap_pars_fragment:ho,alphatest_fragment:mo,alphatest_pars_fragment:_o,aomap_fragment:vo,aomap_pars_fragment:go,batching_pars_vertex:So,batching_vertex:Eo,begin_vertex:Mo,beginnormal_vertex:To,bsdfs:xo,iridescence_fragment:Ao,bumpmap_pars_fragment:Ro,clipping_planes_fragment:Co,clipping_planes_pars_fragment:bo,clipping_planes_pars_vertex:Po,clipping_planes_vertex:Lo,color_fragment:Uo,color_pars_fragment:Do,color_pars_vertex:wo,color_vertex:Io,common:yo,cube_uv_reflection_fragment:No,defaultnormal_vertex:Oo,displacementmap_pars_vertex:Fo,displacementmap_vertex:Bo,emissivemap_fragment:Go,emissivemap_pars_fragment:Ho,colorspace_fragment:Vo,colorspace_pars_fragment:ko,envmap_fragment:zo,envmap_common_pars_fragment:Wo,envmap_pars_fragment:Xo,envmap_pars_vertex:Ko,envmap_physical_pars_fragment:is,envmap_vertex:Yo,fog_vertex:qo,fog_pars_vertex:$o,fog_fragment:Zo,fog_pars_fragment:Qo,gradientmap_pars_fragment:Jo,lightmap_pars_fragment:jo,lights_lambert_fragment:es,lights_lambert_pars_fragment:ts,lights_pars_begin:ns,lights_toon_fragment:rs,lights_toon_pars_fragment:as,lights_phong_fragment:os,lights_phong_pars_fragment:ss,lights_physical_fragment:cs,lights_physical_pars_fragment:ls,lights_fragment_begin:fs,lights_fragment_maps:ds,lights_fragment_end:us,logdepthbuf_fragment:ps,logdepthbuf_pars_fragment:hs,logdepthbuf_pars_vertex:ms,logdepthbuf_vertex:_s,map_fragment:vs,map_pars_fragment:gs,map_particle_fragment:Ss,map_particle_pars_fragment:Es,metalnessmap_fragment:Ms,metalnessmap_pars_fragment:Ts,morphinstance_vertex:xs,morphcolor_vertex:As,morphnormal_vertex:Rs,morphtarget_pars_vertex:Cs,morphtarget_vertex:bs,normal_fragment_begin:Ps,normal_fragment_maps:Ls,normal_pars_fragment:Us,normal_pars_vertex:Ds,normal_vertex:ws,normalmap_pars_fragment:Is,clearcoat_normal_fragment_begin:ys,clearcoat_normal_fragment_maps:Ns,clearcoat_pars_fragment:Os,iridescence_pars_fragment:Fs,opaque_fragment:Bs,packing:Gs,premultiplied_alpha_fragment:Hs,project_vertex:Vs,dithering_fragment:ks,dithering_pars_fragment:zs,roughnessmap_fragment:Ws,roughnessmap_pars_fragment:Xs,shadowmap_pars_fragment:Ks,shadowmap_pars_vertex:Ys,shadowmap_vertex:qs,shadowmask_pars_fragment:$s,skinbase_vertex:Zs,skinning_pars_vertex:Qs,skinning_vertex:Js,skinnormal_vertex:js,specularmap_fragment:ec,specularmap_pars_fragment:tc,tonemapping_fragment:nc,tonemapping_pars_fragment:ic,transmission_fragment:rc,transmission_pars_fragment:ac,uv_pars_fragment:oc,uv_pars_vertex:sc,uv_vertex:cc,worldpos_vertex:lc,background_vert:fc,background_frag:dc,backgroundCube_vert:uc,backgroundCube_frag:pc,cube_vert:hc,cube_frag:mc,depth_vert:_c,depth_frag:vc,distanceRGBA_vert:gc,distanceRGBA_frag:Sc,equirect_vert:Ec,equirect_frag:Mc,linedashed_vert:Tc,linedashed_frag:xc,meshbasic_vert:Ac,meshbasic_frag:Rc,meshlambert_vert:Cc,meshlambert_frag:bc,meshmatcap_vert:Pc,meshmatcap_frag:Lc,meshnormal_vert:Uc,meshnormal_frag:Dc,meshphong_vert:wc,meshphong_frag:Ic,meshphysical_vert:yc,meshphysical_frag:Nc,meshtoon_vert:Oc,meshtoon_frag:Fc,points_vert:Bc,points_frag:Gc,shadow_vert:Hc,shadow_frag:Vc,sprite_vert:kc,sprite_frag:zc},ne={common:{diffuse:{value:new $e(16777215)},opacity:{value:1},map:{value:null},mapTransform:{value:new Oe},alphaMap:{value:null},alphaMapTransform:{value:new Oe},alphaTest:{value:0}},specularmap:{specularMap:{value:null},specularMapTransform:{value:new Oe}},envmap:{envMap:{value:null},envMapRotation:{value:new Oe},flipEnvMap:{value:-1},reflectivity:{value:1},ior:{value:1.5},refractionRatio:{value:.98}},aomap:{aoMap:{value:null},aoMapIntensity:{value:1},aoMapTransform:{value:new Oe}},lightmap:{lightMap:{value:null},lightMapIntensity:{value:1},lightMapTransform:{value:new Oe}},bumpmap:{bumpMap:{value:null},bumpMapTransform:{value:new Oe},bumpScale:{value:1}},normalmap:{normalMap:{value:null},normalMapTransform:{value:new Oe},normalScale:{value:new dt(1,1)}},displacementmap:{displacementMap:{value:null},displacementMapTransform:{value:new Oe},displacementScale:{value:1},displacementBias:{value:0}},emissivemap:{emissiveMap:{value:null},emissiveMapTransform:{value:new Oe}},metalnessmap:{metalnessMap:{value:null},metalnessMapTransform:{value:new Oe}},roughnessmap:{roughnessMap:{value:null},roughnessMapTransform:{value:new Oe}},gradientmap:{gradientMap:{value:null}},fog:{fogDensity:{value:25e-5},fogNear:{value:1},fogFar:{value:2e3},fogColor:{value:new $e(16777215)}},lights:{ambientLightColor:{value:[]},lightProbe:{value:[]},directionalLights:{value:[],properties:{direction:{},color:{}}},directionalLightShadows:{value:[],properties:{shadowIntensity:1,shadowBias:{},shadowNormalBias:{},shadowRadius:{},shadowMapSize:{}}},directionalShadowMap:{value:[]},directionalShadowMatrix:{value:[]},spotLights:{value:[],properties:{color:{},position:{},direction:{},distance:{},coneCos:{},penumbraCos:{},decay:{}}},spotLightShadows:{value:[],properties:{shadowIntensity:1,shadowBias:{},shadowNormalBias:{},shadowRadius:{},shadowMapSize:{}}},spotLightMap:{value:[]},spotShadowMap:{value:[]},spotLightMatrix:{value:[]},pointLights:{value:[],properties:{color:{},position:{},decay:{},distance:{}}},pointLightShadows:{value:[],properties:{shadowIntensity:1,shadowBias:{},shadowNormalBias:{},shadowRadius:{},shadowMapSize:{},shadowCameraNear:{},shadowCameraFar:{}}},pointShadowMap:{value:[]},pointShadowMatrix:{value:[]},hemisphereLights:{value:[],properties:{direction:{},skyColor:{},groundColor:{}}},rectAreaLights:{value:[],properties:{color:{},position:{},width:{},height:{}}},ltc_1:{value:null},ltc_2:{value:null}},points:{diffuse:{value:new $e(16777215)},opacity:{value:1},size:{value:1},scale:{value:1},map:{value:null},alphaMap:{value:null},alphaMapTransform:{value:new Oe},alphaTest:{value:0},uvTransform:{value:new Oe}},sprite:{diffuse:{value:new $e(16777215)},opacity:{value:1},center:{value:new dt(.5,.5)},rotation:{value:0},map:{value:null},mapTransform:{value:new Oe},alphaMap:{value:null},alphaMapTransform:{value:new Oe},alphaTest:{value:0}}},gt={basic:{uniforms:lt([ne.common,ne.specularmap,ne.envmap,ne.aomap,ne.lightmap,ne.fog]),vertexShader:De.meshbasic_vert,fragmentShader:De.meshbasic_frag},lambert:{uniforms:lt([ne.common,ne.specularmap,ne.envmap,ne.aomap,ne.lightmap,ne.emissivemap,ne.bumpmap,ne.normalmap,ne.displacementmap,ne.fog,ne.lights,{emissive:{value:new $e(0)}}]),vertexShader:De.meshlambert_vert,fragmentShader:De.meshlambert_frag},phong:{uniforms:lt([ne.common,ne.specularmap,ne.envmap,ne.aomap,ne.lightmap,ne.emissivemap,ne.bumpmap,ne.normalmap,ne.displacementmap,ne.fog,ne.lights,{emissive:{value:new $e(0)},specular:{value:new $e(1118481)},shininess:{value:30}}]),vertexShader:De.meshphong_vert,fragmentShader:De.meshphong_frag},standard:{uniforms:lt([ne.common,ne.envmap,ne.aomap,ne.lightmap,ne.emissivemap,ne.bumpmap,ne.normalmap,ne.displacementmap,ne.roughnessmap,ne.metalnessmap,ne.fog,ne.lights,{emissive:{value:new $e(0)},roughness:{value:1},metalness:{value:0},envMapIntensity:{value:1}}]),vertexShader:De.meshphysical_vert,fragmentShader:De.meshphysical_frag},toon:{uniforms:lt([ne.common,ne.aomap,ne.lightmap,ne.emissivemap,ne.bumpmap,ne.normalmap,ne.displacementmap,ne.gradientmap,ne.fog,ne.lights,{emissive:{value:new $e(0)}}]),vertexShader:De.meshtoon_vert,fragmentShader:De.meshtoon_frag},matcap:{uniforms:lt([ne.common,ne.bumpmap,ne.normalmap,ne.displacementmap,ne.fog,{matcap:{value:null}}]),vertexShader:De.meshmatcap_vert,fragmentShader:De.meshmatcap_frag},points:{uniforms:lt([ne.points,ne.fog]),vertexShader:De.points_vert,fragmentShader:De.points_frag},dashed:{uniforms:lt([ne.common,ne.fog,{scale:{value:1},dashSize:{value:1},totalSize:{value:2}}]),vertexShader:De.linedashed_vert,fragmentShader:De.linedashed_frag},depth:{uniforms:lt([ne.common,ne.displacementmap]),vertexShader:De.depth_vert,fragmentShader:De.depth_frag},normal:{uniforms:lt([ne.common,ne.bumpmap,ne.normalmap,ne.displacementmap,{opacity:{value:1}}]),vertexShader:De.meshnormal_vert,fragmentShader:De.meshnormal_frag},sprite:{uniforms:lt([ne.sprite,ne.fog]),vertexShader:De.sprite_vert,fragmentShader:De.sprite_frag},background:{uniforms:{uvTransform:{value:new Oe},t2D:{value:null},backgroundIntensity:{value:1}},vertexShader:De.background_vert,fragmentShader:De.background_frag},backgroundCube:{uniforms:{envMap:{value:null},flipEnvMap:{value:-1},backgroundBlurriness:{value:0},backgroundIntensity:{value:1},backgroundRotation:{value:new Oe}},vertexShader:De.backgroundCube_vert,fragmentShader:De.backgroundCube_frag},cube:{uniforms:{tCube:{value:null},tFlip:{value:-1},opacity:{value:1}},vertexShader:De.cube_vert,fragmentShader:De.cube_frag},equirect:{uniforms:{tEquirect:{value:null}},vertexShader:De.equirect_vert,fragmentShader:De.equirect_frag},distanceRGBA:{uniforms:lt([ne.common,ne.displacementmap,{referencePosition:{value:new We},nearDistance:{value:1},farDistance:{value:1e3}}]),vertexShader:De.distanceRGBA_vert,fragmentShader:De.distanceRGBA_frag},shadow:{uniforms:lt([ne.lights,ne.fog,{color:{value:new $e(0)},opacity:{value:1}}]),vertexShader:De.shadow_vert,fragmentShader:De.shadow_frag}};gt.physical={uniforms:lt([gt.standard.uniforms,{clearcoat:{value:0},clearcoatMap:{value:null},clearcoatMapTransform:{value:new Oe},clearcoatNormalMap:{value:null},clearcoatNormalMapTransform:{value:new Oe},clearcoatNormalScale:{value:new dt(1,1)},clearcoatRoughness:{value:0},clearcoatRoughnessMap:{value:null},clearcoatRoughnessMapTransform:{value:new Oe},dispersion:{value:0},iridescence:{value:0},iridescenceMap:{value:null},iridescenceMapTransform:{value:new Oe},iridescenceIOR:{value:1.3},iridescenceThicknessMinimum:{value:100},iridescenceThicknessMaximum:{value:400},iridescenceThicknessMap:{value:null},iridescenceThicknessMapTransform:{value:new Oe},sheen:{value:0},sheenColor:{value:new $e(0)},sheenColorMap:{value:null},sheenColorMapTransform:{value:new Oe},sheenRoughness:{value:1},sheenRoughnessMap:{value:null},sheenRoughnessMapTransform:{value:new Oe},transmission:{value:0},transmissionMap:{value:null},transmissionMapTransform:{value:new Oe},transmissionSamplerSize:{value:new dt},transmissionSamplerMap:{value:null},thickness:{value:0},thicknessMap:{value:null},thicknessMapTransform:{value:new Oe},attenuationDistance:{value:0},attenuationColor:{value:new $e(0)},specularColor:{value:new $e(1,1,1)},specularColorMap:{value:null},specularColorMapTransform:{value:new Oe},specularIntensity:{value:1},specularIntensityMap:{value:null},specularIntensityMapTransform:{value:new Oe},anisotropyVector:{value:new dt},anisotropyMap:{value:null},anisotropyMapTransform:{value:new Oe}}]),vertexShader:De.meshphysical_vert,fragmentShader:De.meshphysical_frag};var rn={r:0,b:0,g:0},bt=new fr,Wc=new Vt;function Xc(e,n,t,i,c,o,h){let d=new $e(0),C=o===!0?0:1,M,D,T=null,g=0,A=null;function N(x){let _=x.isScene===!0?x.background:null;return _&&_.isTexture&&(_=(x.backgroundBlurriness>0?t:n).get(_)),_}function L(x){let _=!1,H=N(x);H===null?r(d,C):H&&H.isColor&&(r(H,1),_=!0);let P=e.xr.getEnvironmentBlendMode();P==="additive"?i.buffers.color.setClear(0,0,0,1,h):P==="alpha-blend"&&i.buffers.color.setClear(0,0,0,0,h),(e.autoClear||_)&&(i.buffers.depth.setTest(!0),i.buffers.depth.setMask(!0),i.buffers.color.setMask(!0),e.clear(e.autoClearColor,e.autoClearDepth,e.autoClearStencil))}function l(x,_){let H=N(_);H&&(H.isCubeTexture||H.mapping===mn)?(D===void 0&&(D=new xt(new lr(1,1,1),new It({name:"BackgroundCubeMaterial",uniforms:oi(gt.backgroundCube.uniforms),vertexShader:gt.backgroundCube.vertexShader,fragmentShader:gt.backgroundCube.fragmentShader,side:mt,depthTest:!1,depthWrite:!1,fog:!1,allowOverride:!1})),D.geometry.deleteAttribute("normal"),D.geometry.deleteAttribute("uv"),D.onBeforeRender=function(P,y,G){this.matrixWorld.copyPosition(G.matrixWorld)},Object.defineProperty(D.material,"envMap",{get:function(){return this.uniforms.envMap.value}}),c.update(D)),bt.copy(_.backgroundRotation),bt.x*=-1,bt.y*=-1,bt.z*=-1,H.isCubeTexture&&H.isRenderTargetTexture===!1&&(bt.y*=-1,bt.z*=-1),D.material.uniforms.envMap.value=H,D.material.uniforms.flipEnvMap.value=H.isCubeTexture&&H.isRenderTargetTexture===!1?-1:1,D.material.uniforms.backgroundBlurriness.value=_.backgroundBlurriness,D.material.uniforms.backgroundIntensity.value=_.backgroundIntensity,D.material.uniforms.backgroundRotation.value.setFromMatrix4(Wc.makeRotationFromEuler(bt)),D.material.toneMapped=tt.getTransfer(H.colorSpace)!==Ye,(T!==H||g!==H.version||A!==e.toneMapping)&&(D.material.needsUpdate=!0,T=H,g=H.version,A=e.toneMapping),D.layers.enableAll(),x.unshift(D,D.geometry,D.material,0,0,null)):H&&H.isTexture&&(M===void 0&&(M=new xt(new dr(2,2),new It({name:"BackgroundMaterial",uniforms:oi(gt.background.uniforms),vertexShader:gt.background.vertexShader,fragmentShader:gt.background.fragmentShader,side:Zt,depthTest:!1,depthWrite:!1,fog:!1,allowOverride:!1})),M.geometry.deleteAttribute("normal"),Object.defineProperty(M.material,"map",{get:function(){return this.uniforms.t2D.value}}),c.update(M)),M.material.uniforms.t2D.value=H,M.material.uniforms.backgroundIntensity.value=_.backgroundIntensity,M.material.toneMapped=tt.getTransfer(H.colorSpace)!==Ye,H.matrixAutoUpdate===!0&&H.updateMatrix(),M.material.uniforms.uvTransform.value.copy(H.matrix),(T!==H||g!==H.version||A!==e.toneMapping)&&(M.material.needsUpdate=!0,T=H,g=H.version,A=e.toneMapping),M.layers.enableAll(),x.unshift(M,M.geometry,M.material,0,0,null))}function r(x,_){x.getRGB(rn,ur(e)),i.buffers.color.setClear(rn.r,rn.g,rn.b,_,h)}function U(){D!==void 0&&(D.geometry.dispose(),D.material.dispose(),D=void 0),M!==void 0&&(M.geometry.dispose(),M.material.dispose(),M=void 0)}return{getClearColor:function(){return d},setClearColor:function(x,_=1){d.set(x),C=_,r(d,C)},getClearAlpha:function(){return C},setClearAlpha:function(x){C=x,r(d,C)},render:L,addToRenderList:l,dispose:U}}function Kc(e,n){let t=e.getParameter(e.MAX_VERTEX_ATTRIBS),i={},c=g(null),o=c,h=!1;function d(f,R,Y,V,K){let J=!1,W=T(V,Y,R);o!==W&&(o=W,M(o.object)),J=A(f,V,Y,K),J&&N(f,V,Y,K),K!==null&&n.update(K,e.ELEMENT_ARRAY_BUFFER),(J||h)&&(h=!1,_(f,R,Y,V),K!==null&&e.bindBuffer(e.ELEMENT_ARRAY_BUFFER,n.get(K).buffer))}function C(){return e.createVertexArray()}function M(f){return e.bindVertexArray(f)}function D(f){return e.deleteVertexArray(f)}function T(f,R,Y){let V=Y.wireframe===!0,K=i[f.id];K===void 0&&(K={},i[f.id]=K);let J=K[R.id];J===void 0&&(J={},K[R.id]=J);let W=J[V];return W===void 0&&(W=g(C()),J[V]=W),W}function g(f){let R=[],Y=[],V=[];for(let K=0;K<t;K++)R[K]=0,Y[K]=0,V[K]=0;return{geometry:null,program:null,wireframe:!1,newAttributes:R,enabledAttributes:Y,attributeDivisors:V,object:f,attributes:{},index:null}}function A(f,R,Y,V){let K=o.attributes,J=R.attributes,W=0,ee=Y.getAttributes();for(let F in ee)if(ee[F].location>=0){let Ae=K[F],we=J[F];if(we===void 0&&(F==="instanceMatrix"&&f.instanceMatrix&&(we=f.instanceMatrix),F==="instanceColor"&&f.instanceColor&&(we=f.instanceColor)),Ae===void 0||Ae.attribute!==we||we&&Ae.data!==we.data)return!0;W++}return o.attributesNum!==W||o.index!==V}function N(f,R,Y,V){let K={},J=R.attributes,W=0,ee=Y.getAttributes();for(let F in ee)if(ee[F].location>=0){let Ae=J[F];Ae===void 0&&(F==="instanceMatrix"&&f.instanceMatrix&&(Ae=f.instanceMatrix),F==="instanceColor"&&f.instanceColor&&(Ae=f.instanceColor));let we={};we.attribute=Ae,Ae&&Ae.data&&(we.data=Ae.data),K[F]=we,W++}o.attributes=K,o.attributesNum=W,o.index=V}function L(){let f=o.newAttributes;for(let R=0,Y=f.length;R<Y;R++)f[R]=0}function l(f){r(f,0)}function r(f,R){let Y=o.newAttributes,V=o.enabledAttributes,K=o.attributeDivisors;Y[f]=1,V[f]===0&&(e.enableVertexAttribArray(f),V[f]=1),K[f]!==R&&(e.vertexAttribDivisor(f,R),K[f]=R)}function U(){let f=o.newAttributes,R=o.enabledAttributes;for(let Y=0,V=R.length;Y<V;Y++)R[Y]!==f[Y]&&(e.disableVertexAttribArray(Y),R[Y]=0)}function x(f,R,Y,V,K,J,W){W===!0?e.vertexAttribIPointer(f,R,Y,K,J):e.vertexAttribPointer(f,R,Y,V,K,J)}function _(f,R,Y,V){L();let K=V.attributes,J=Y.getAttributes(),W=R.defaultAttributeValues;for(let ee in J){let F=J[ee];if(F.location>=0){let Se=K[ee];if(Se===void 0&&(ee==="instanceMatrix"&&f.instanceMatrix&&(Se=f.instanceMatrix),ee==="instanceColor"&&f.instanceColor&&(Se=f.instanceColor)),Se!==void 0){let Ae=Se.normalized,we=Se.itemSize,He=n.get(Se);if(He===void 0)continue;let je=He.buffer,k=He.type,j=He.bytesPerElement,_e=k===e.INT||k===e.UNSIGNED_INT||Se.gpuType===pr;if(Se.isInterleavedBufferAttribute){let oe=Se.data,ve=oe.stride,Fe=Se.offset;if(oe.isInstancedInterleavedBuffer){for(let Re=0;Re<F.locationSize;Re++)r(F.location+Re,oe.meshPerAttribute);f.isInstancedMesh!==!0&&V._maxInstanceCount===void 0&&(V._maxInstanceCount=oe.meshPerAttribute*oe.count)}else for(let Re=0;Re<F.locationSize;Re++)l(F.location+Re);e.bindBuffer(e.ARRAY_BUFFER,je);for(let Re=0;Re<F.locationSize;Re++)x(F.location+Re,we/F.locationSize,k,Ae,ve*j,(Fe+we/F.locationSize*Re)*j,_e)}else{if(Se.isInstancedBufferAttribute){for(let oe=0;oe<F.locationSize;oe++)r(F.location+oe,Se.meshPerAttribute);f.isInstancedMesh!==!0&&V._maxInstanceCount===void 0&&(V._maxInstanceCount=Se.meshPerAttribute*Se.count)}else for(let oe=0;oe<F.locationSize;oe++)l(F.location+oe);e.bindBuffer(e.ARRAY_BUFFER,je);for(let oe=0;oe<F.locationSize;oe++)x(F.location+oe,we/F.locationSize,k,Ae,we*j,we/F.locationSize*oe*j,_e)}}else if(W!==void 0){let Ae=W[ee];if(Ae!==void 0)switch(Ae.length){case 2:e.vertexAttrib2fv(F.location,Ae);break;case 3:e.vertexAttrib3fv(F.location,Ae);break;case 4:e.vertexAttrib4fv(F.location,Ae);break;default:e.vertexAttrib1fv(F.location,Ae)}}}}U()}function H(){G();for(let f in i){let R=i[f];for(let Y in R){let V=R[Y];for(let K in V)D(V[K].object),delete V[K];delete R[Y]}delete i[f]}}function P(f){if(i[f.id]===void 0)return;let R=i[f.id];for(let Y in R){let V=R[Y];for(let K in V)D(V[K].object),delete V[K];delete R[Y]}delete i[f.id]}function y(f){for(let R in i){let Y=i[R];if(Y[f.id]===void 0)continue;let V=Y[f.id];for(let K in V)D(V[K].object),delete V[K];delete Y[f.id]}}function G(){p(),h=!0,o!==c&&(o=c,M(o.object))}function p(){c.geometry=null,c.program=null,c.wireframe=!1}return{setup:d,reset:G,resetDefaultState:p,dispose:H,releaseStatesOfGeometry:P,releaseStatesOfProgram:y,initAttributes:L,enableAttribute:l,disableUnusedAttributes:U}}function Yc(e,n,t){let i;function c(M){i=M}function o(M,D){e.drawArrays(i,M,D),t.update(D,i,1)}function h(M,D,T){T!==0&&(e.drawArraysInstanced(i,M,D,T),t.update(D,i,T))}function d(M,D,T){if(T===0)return;n.get("WEBGL_multi_draw").multiDrawArraysWEBGL(i,M,0,D,0,T);let A=0;for(let N=0;N<T;N++)A+=D[N];t.update(A,i,1)}function C(M,D,T,g){if(T===0)return;let A=n.get("WEBGL_multi_draw");if(A===null)for(let N=0;N<M.length;N++)h(M[N],D[N],g[N]);else{A.multiDrawArraysInstancedWEBGL(i,M,0,D,0,g,0,T);let N=0;for(let L=0;L<T;L++)N+=D[L]*g[L];t.update(N,i,1)}}this.setMode=c,this.render=o,this.renderInstances=h,this.renderMultiDraw=d,this.renderMultiDrawInstances=C}function qc(e,n,t,i){let c;function o(){if(c!==void 0)return c;if(n.has("EXT_texture_filter_anisotropic")===!0){let y=n.get("EXT_texture_filter_anisotropic");c=e.getParameter(y.MAX_TEXTURE_MAX_ANISOTROPY_EXT)}else c=0;return c}function h(y){return!(y!==Tt&&i.convert(y)!==e.getParameter(e.IMPLEMENTATION_COLOR_READ_FORMAT))}function d(y){let G=y===_n&&(n.has("EXT_color_buffer_half_float")||n.has("EXT_color_buffer_float"));return!(y!==yt&&i.convert(y)!==e.getParameter(e.IMPLEMENTATION_COLOR_READ_TYPE)&&y!==Dt&&!G)}function C(y){if(y==="highp"){if(e.getShaderPrecisionFormat(e.VERTEX_SHADER,e.HIGH_FLOAT).precision>0&&e.getShaderPrecisionFormat(e.FRAGMENT_SHADER,e.HIGH_FLOAT).precision>0)return"highp";y="mediump"}return y==="mediump"&&e.getShaderPrecisionFormat(e.VERTEX_SHADER,e.MEDIUM_FLOAT).precision>0&&e.getShaderPrecisionFormat(e.FRAGMENT_SHADER,e.MEDIUM_FLOAT).precision>0?"mediump":"lowp"}let M=t.precision!==void 0?t.precision:"highp",D=C(M);D!==M&&(console.warn("THREE.WebGLRenderer:",M,"not supported, using",D,"instead."),M=D);let T=t.logarithmicDepthBuffer===!0,g=t.reverseDepthBuffer===!0&&n.has("EXT_clip_control"),A=e.getParameter(e.MAX_TEXTURE_IMAGE_UNITS),N=e.getParameter(e.MAX_VERTEX_TEXTURE_IMAGE_UNITS),L=e.getParameter(e.MAX_TEXTURE_SIZE),l=e.getParameter(e.MAX_CUBE_MAP_TEXTURE_SIZE),r=e.getParameter(e.MAX_VERTEX_ATTRIBS),U=e.getParameter(e.MAX_VERTEX_UNIFORM_VECTORS),x=e.getParameter(e.MAX_VARYING_VECTORS),_=e.getParameter(e.MAX_FRAGMENT_UNIFORM_VECTORS),H=N>0,P=e.getParameter(e.MAX_SAMPLES);return{isWebGL2:!0,getMaxAnisotropy:o,getMaxPrecision:C,textureFormatReadable:h,textureTypeReadable:d,precision:M,logarithmicDepthBuffer:T,reverseDepthBuffer:g,maxTextures:A,maxVertexTextures:N,maxTextureSize:L,maxCubemapSize:l,maxAttributes:r,maxVertexUniforms:U,maxVaryings:x,maxFragmentUniforms:_,vertexTextures:H,maxSamples:P}}function $c(e){let n=this,t=null,i=0,c=!1,o=!1,h=new Br,d=new Oe,C={value:null,needsUpdate:!1};this.uniform=C,this.numPlanes=0,this.numIntersection=0,this.init=function(T,g){let A=T.length!==0||g||i!==0||c;return c=g,i=T.length,A},this.beginShadows=function(){o=!0,D(null)},this.endShadows=function(){o=!1},this.setGlobalState=function(T,g){t=D(T,g,0)},this.setState=function(T,g,A){let N=T.clippingPlanes,L=T.clipIntersection,l=T.clipShadows,r=e.get(T);if(!c||N===null||N.length===0||o&&!l)o?D(null):M();else{let U=o?0:i,x=U*4,_=r.clippingState||null;C.value=_,_=D(N,g,x,A);for(let H=0;H!==x;++H)_[H]=t[H];r.clippingState=_,this.numIntersection=L?this.numPlanes:0,this.numPlanes+=U}};function M(){C.value!==t&&(C.value=t,C.needsUpdate=i>0),n.numPlanes=i,n.numIntersection=0}function D(T,g,A,N){let L=T!==null?T.length:0,l=null;if(L!==0){if(l=C.value,N!==!0||l===null){let r=A+L*4,U=g.matrixWorldInverse;d.getNormalMatrix(U),(l===null||l.length<r)&&(l=new Float32Array(r));for(let x=0,_=A;x!==L;++x,_+=4)h.copy(T[x]).applyMatrix4(U,d),h.normal.toArray(l,_),l[_+3]=h.constant}C.value=l,C.needsUpdate=!0}return n.numPlanes=L,n.numIntersection=0,l}}function Zc(e){let n=new WeakMap;function t(h,d){return d===yn?h.mapping=Qt:d===Nn&&(h.mapping=kt),h}function i(h){if(h&&h.isTexture){let d=h.mapping;if(d===yn||d===Nn)if(n.has(h)){let C=n.get(h).texture;return t(C,h.mapping)}else{let C=h.image;if(C&&C.height>0){let M=new Gr(C.height);return M.fromEquirectangularTexture(e,h),n.set(h,M),h.addEventListener("dispose",c),t(M.texture,h.mapping)}else return null}}return h}function c(h){let d=h.target;d.removeEventListener("dispose",c);let C=n.get(d);C!==void 0&&(n.delete(d),C.dispose())}function o(){n=new WeakMap}return{get:i,dispose:o}}var Gt=4,Gi=[.125,.215,.35,.446,.526,.582],Ut=20,Pn=new Hr,Hi=new $e,Ln=null,Un=0,Dn=0,wn=!1,Lt=(1+Math.sqrt(5))/2,Ot=1/Lt,Vi=[new We(-Lt,Ot,0),new We(Lt,Ot,0),new We(-Ot,0,Lt),new We(Ot,0,Lt),new We(0,Lt,-Ot),new We(0,Lt,Ot),new We(-1,1,-1),new We(1,1,-1),new We(-1,1,1),new We(1,1,1)],Qc=new We,hn=class{constructor(n){this._renderer=n,this._pingPongRenderTarget=null,this._lodMax=0,this._cubeSize=0,this._lodPlanes=[],this._sizeLods=[],this._sigmas=[],this._blurMaterial=null,this._cubemapMaterial=null,this._equirectMaterial=null,this._compileMaterial(this._blurMaterial)}fromScene(n,t=0,i=.1,c=100,o={}){let{size:h=256,position:d=Qc}=o;Ln=this._renderer.getRenderTarget(),Un=this._renderer.getActiveCubeFace(),Dn=this._renderer.getActiveMipmapLevel(),wn=this._renderer.xr.enabled,this._renderer.xr.enabled=!1,this._setSize(h);let C=this._allocateTargets();return C.depthBuffer=!0,this._sceneToCubeUV(n,i,c,C,d),t>0&&this._blur(C,0,0,t),this._applyPMREM(C),this._cleanup(C),C}fromEquirectangular(n,t=null){return this._fromTexture(n,t)}fromCubemap(n,t=null){return this._fromTexture(n,t)}compileCubemapShader(){this._cubemapMaterial===null&&(this._cubemapMaterial=Wi(),this._compileMaterial(this._cubemapMaterial))}compileEquirectangularShader(){this._equirectMaterial===null&&(this._equirectMaterial=zi(),this._compileMaterial(this._equirectMaterial))}dispose(){this._dispose(),this._cubemapMaterial!==null&&this._cubemapMaterial.dispose(),this._equirectMaterial!==null&&this._equirectMaterial.dispose()}_setSize(n){this._lodMax=Math.floor(Math.log2(n)),this._cubeSize=Math.pow(2,this._lodMax)}_dispose(){this._blurMaterial!==null&&this._blurMaterial.dispose(),this._pingPongRenderTarget!==null&&this._pingPongRenderTarget.dispose();for(let n=0;n<this._lodPlanes.length;n++)this._lodPlanes[n].dispose()}_cleanup(n){this._renderer.setRenderTarget(Ln,Un,Dn),this._renderer.xr.enabled=wn,n.scissorTest=!1,an(n,0,0,n.width,n.height)}_fromTexture(n,t){n.mapping===Qt||n.mapping===kt?this._setSize(n.image.length===0?16:n.image[0].width||n.image[0].image.width):this._setSize(n.image.width/4),Ln=this._renderer.getRenderTarget(),Un=this._renderer.getActiveCubeFace(),Dn=this._renderer.getActiveMipmapLevel(),wn=this._renderer.xr.enabled,this._renderer.xr.enabled=!1;let i=t||this._allocateTargets();return this._textureToCubeUV(n,i),this._applyPMREM(i),this._cleanup(i),i}_allocateTargets(){let n=3*Math.max(this._cubeSize,112),t=4*this._cubeSize,i={magFilter:Bt,minFilter:Bt,generateMipmaps:!1,type:_n,format:Tt,colorSpace:vn,depthBuffer:!1},c=ki(n,t,i);if(this._pingPongRenderTarget===null||this._pingPongRenderTarget.width!==n||this._pingPongRenderTarget.height!==t){this._pingPongRenderTarget!==null&&this._dispose(),this._pingPongRenderTarget=ki(n,t,i);let{_lodMax:o}=this;({sizeLods:this._sizeLods,lodPlanes:this._lodPlanes,sigmas:this._sigmas}=Jc(o)),this._blurMaterial=jc(o,n,t)}return c}_compileMaterial(n){let t=new xt(this._lodPlanes[0],n);this._renderer.compile(t,Pn)}_sceneToCubeUV(n,t,i,c,o){let C=new sn(90,1,t,i),M=[1,-1,1,1,1,1],D=[1,1,1,-1,-1,-1],T=this._renderer,g=T.autoClear,A=T.toneMapping;T.getClearColor(Hi),T.toneMapping=At,T.autoClear=!1;let N=new Vr({name:"PMREM.Background",side:mt,depthWrite:!1,depthTest:!1}),L=new xt(new lr,N),l=!1,r=n.background;r?r.isColor&&(N.color.copy(r),n.background=null,l=!0):(N.color.copy(Hi),l=!0);for(let U=0;U<6;U++){let x=U%3;x===0?(C.up.set(0,M[U],0),C.position.set(o.x,o.y,o.z),C.lookAt(o.x+D[U],o.y,o.z)):x===1?(C.up.set(0,0,M[U]),C.position.set(o.x,o.y,o.z),C.lookAt(o.x,o.y+D[U],o.z)):(C.up.set(0,M[U],0),C.position.set(o.x,o.y,o.z),C.lookAt(o.x,o.y,o.z+D[U]));let _=this._cubeSize;an(c,x*_,U>2?_:0,_,_),T.setRenderTarget(c),l&&T.render(L,C),T.render(n,C)}L.geometry.dispose(),L.material.dispose(),T.toneMapping=A,T.autoClear=g,n.background=r}_textureToCubeUV(n,t){let i=this._renderer,c=n.mapping===Qt||n.mapping===kt;c?(this._cubemapMaterial===null&&(this._cubemapMaterial=Wi()),this._cubemapMaterial.uniforms.flipEnvMap.value=n.isRenderTargetTexture===!1?-1:1):this._equirectMaterial===null&&(this._equirectMaterial=zi());let o=c?this._cubemapMaterial:this._equirectMaterial,h=new xt(this._lodPlanes[0],o),d=o.uniforms;d.envMap.value=n;let C=this._cubeSize;an(t,0,0,3*C,2*C),i.setRenderTarget(t),i.render(h,Pn)}_applyPMREM(n){let t=this._renderer,i=t.autoClear;t.autoClear=!1;let c=this._lodPlanes.length;for(let o=1;o<c;o++){let h=Math.sqrt(this._sigmas[o]*this._sigmas[o]-this._sigmas[o-1]*this._sigmas[o-1]),d=Vi[(c-o-1)%Vi.length];this._blur(n,o-1,o,h,d)}t.autoClear=i}_blur(n,t,i,c,o){let h=this._pingPongRenderTarget;this._halfBlur(n,h,t,i,c,"latitudinal",o),this._halfBlur(h,n,i,i,c,"longitudinal",o)}_halfBlur(n,t,i,c,o,h,d){let C=this._renderer,M=this._blurMaterial;h!=="latitudinal"&&h!=="longitudinal"&&console.error("blur direction must be either latitudinal or longitudinal!");let D=3,T=new xt(this._lodPlanes[c],M),g=M.uniforms,A=this._sizeLods[i]-1,N=isFinite(o)?Math.PI/(2*A):2*Math.PI/(2*Ut-1),L=o/N,l=isFinite(o)?1+Math.floor(D*L):Ut;l>Ut&&console.warn(`sigmaRadians, ${o}, is too large and will clip, as it requested ${l} samples when the maximum is set to ${Ut}`);let r=[],U=0;for(let y=0;y<Ut;++y){let G=y/L,p=Math.exp(-G*G/2);r.push(p),y===0?U+=p:y<l&&(U+=2*p)}for(let y=0;y<r.length;y++)r[y]=r[y]/U;g.envMap.value=n.texture,g.samples.value=l,g.weights.value=r,g.latitudinal.value=h==="latitudinal",d&&(g.poleAxis.value=d);let{_lodMax:x}=this;g.dTheta.value=N,g.mipInt.value=x-i;let _=this._sizeLods[c],H=3*_*(c>x-Gt?c-x+Gt:0),P=4*(this._cubeSize-_);an(t,H,P,3*_,2*_),C.setRenderTarget(t),C.render(T,Pn)}};function Jc(e){let n=[],t=[],i=[],c=e,o=e-Gt+1+Gi.length;for(let h=0;h<o;h++){let d=Math.pow(2,c);t.push(d);let C=1/d;h>e-Gt?C=Gi[h-e+Gt-1]:h===0&&(C=0),i.push(C);let M=1/(d-2),D=-M,T=1+M,g=[D,D,T,D,T,T,D,D,T,T,D,T],A=6,N=6,L=3,l=2,r=1,U=new Float32Array(L*N*A),x=new Float32Array(l*N*A),_=new Float32Array(r*N*A);for(let P=0;P<A;P++){let y=P%3*2/3-1,G=P>2?0:-1,p=[y,G,0,y+2/3,G,0,y+2/3,G+1,0,y,G,0,y+2/3,G+1,0,y,G+1,0];U.set(p,L*N*P),x.set(g,l*N*P);let f=[P,P,P,P,P,P];_.set(f,r*N*P)}let H=new hr;H.setAttribute("position",new cn(U,L)),H.setAttribute("uv",new cn(x,l)),H.setAttribute("faceIndex",new cn(_,r)),n.push(H),c>Gt&&c--}return{lodPlanes:n,sizeLods:t,sigmas:i}}function ki(e,n,t){let i=new zt(e,n,t);return i.texture.mapping=mn,i.texture.name="PMREM.cubeUv",i.scissorTest=!0,i}function an(e,n,t,i,c){e.viewport.set(n,t,i,c),e.scissor.set(n,t,i,c)}function jc(e,n,t){let i=new Float32Array(Ut),c=new We(0,1,0);return new It({name:"SphericalGaussianBlur",defines:{n:Ut,CUBEUV_TEXEL_WIDTH:1/n,CUBEUV_TEXEL_HEIGHT:1/t,CUBEUV_MAX_MIP:`${e}.0`},uniforms:{envMap:{value:null},samples:{value:1},weights:{value:i},latitudinal:{value:!1},dTheta:{value:0},mipInt:{value:0},poleAxis:{value:c}},vertexShader:Jn(),fragmentShader:`

			precision mediump float;
			precision mediump int;

			varying vec3 vOutputDirection;

			uniform sampler2D envMap;
			uniform int samples;
			uniform float weights[ n ];
			uniform bool latitudinal;
			uniform float dTheta;
			uniform float mipInt;
			uniform vec3 poleAxis;

			#define ENVMAP_TYPE_CUBE_UV
			#include <cube_uv_reflection_fragment>

			vec3 getSample( float theta, vec3 axis ) {

				float cosTheta = cos( theta );
				// Rodrigues' axis-angle rotation
				vec3 sampleDirection = vOutputDirection * cosTheta
					+ cross( axis, vOutputDirection ) * sin( theta )
					+ axis * dot( axis, vOutputDirection ) * ( 1.0 - cosTheta );

				return bilinearCubeUV( envMap, sampleDirection, mipInt );

			}

			void main() {

				vec3 axis = latitudinal ? poleAxis : cross( poleAxis, vOutputDirection );

				if ( all( equal( axis, vec3( 0.0 ) ) ) ) {

					axis = vec3( vOutputDirection.z, 0.0, - vOutputDirection.x );

				}

				axis = normalize( axis );

				gl_FragColor = vec4( 0.0, 0.0, 0.0, 1.0 );
				gl_FragColor.rgb += weights[ 0 ] * getSample( 0.0, axis );

				for ( int i = 1; i < n; i++ ) {

					if ( i >= samples ) {

						break;

					}

					float theta = dTheta * float( i );
					gl_FragColor.rgb += weights[ i ] * getSample( -1.0 * theta, axis );
					gl_FragColor.rgb += weights[ i ] * getSample( theta, axis );

				}

			}
		`,blending:wt,depthTest:!1,depthWrite:!1})}function zi(){return new It({name:"EquirectangularToCubeUV",uniforms:{envMap:{value:null}},vertexShader:Jn(),fragmentShader:`

			precision mediump float;
			precision mediump int;

			varying vec3 vOutputDirection;

			uniform sampler2D envMap;

			#include <common>

			void main() {

				vec3 outputDirection = normalize( vOutputDirection );
				vec2 uv = equirectUv( outputDirection );

				gl_FragColor = vec4( texture2D ( envMap, uv ).rgb, 1.0 );

			}
		`,blending:wt,depthTest:!1,depthWrite:!1})}function Wi(){return new It({name:"CubemapToCubeUV",uniforms:{envMap:{value:null},flipEnvMap:{value:-1}},vertexShader:Jn(),fragmentShader:`

			precision mediump float;
			precision mediump int;

			uniform float flipEnvMap;

			varying vec3 vOutputDirection;

			uniform samplerCube envMap;

			void main() {

				gl_FragColor = textureCube( envMap, vec3( flipEnvMap * vOutputDirection.x, vOutputDirection.yz ) );

			}
		`,blending:wt,depthTest:!1,depthWrite:!1})}function Jn(){return`

		precision mediump float;
		precision mediump int;

		attribute float faceIndex;

		varying vec3 vOutputDirection;

		// RH coordinate system; PMREM face-indexing convention
		vec3 getDirection( vec2 uv, float face ) {

			uv = 2.0 * uv - 1.0;

			vec3 direction = vec3( uv, 1.0 );

			if ( face == 0.0 ) {

				direction = direction.zyx; // ( 1, v, u ) pos x

			} else if ( face == 1.0 ) {

				direction = direction.xzy;
				direction.xz *= -1.0; // ( -u, 1, -v ) pos y

			} else if ( face == 2.0 ) {

				direction.x *= -1.0; // ( -u, v, 1 ) pos z

			} else if ( face == 3.0 ) {

				direction = direction.zyx;
				direction.xz *= -1.0; // ( -1, v, -u ) neg x

			} else if ( face == 4.0 ) {

				direction = direction.xzy;
				direction.xy *= -1.0; // ( -u, -1, v ) neg y

			} else if ( face == 5.0 ) {

				direction.z *= -1.0; // ( u, v, -1 ) neg z

			}

			return direction;

		}

		void main() {

			vOutputDirection = getDirection( uv, faceIndex );
			gl_Position = vec4( position, 1.0 );

		}
	`}function el(e){let n=new WeakMap,t=null;function i(d){if(d&&d.isTexture){let C=d.mapping,M=C===yn||C===Nn,D=C===Qt||C===kt;if(M||D){let T=n.get(d),g=T!==void 0?T.texture.pmremVersion:0;if(d.isRenderTargetTexture&&d.pmremVersion!==g)return t===null&&(t=new hn(e)),T=M?t.fromEquirectangular(d,T):t.fromCubemap(d,T),T.texture.pmremVersion=d.pmremVersion,n.set(d,T),T.texture;if(T!==void 0)return T.texture;{let A=d.image;return M&&A&&A.height>0||D&&A&&c(A)?(t===null&&(t=new hn(e)),T=M?t.fromEquirectangular(d):t.fromCubemap(d),T.texture.pmremVersion=d.pmremVersion,n.set(d,T),d.addEventListener("dispose",o),T.texture):null}}}return d}function c(d){let C=0,M=6;for(let D=0;D<M;D++)d[D]!==void 0&&C++;return C===M}function o(d){let C=d.target;C.removeEventListener("dispose",o);let M=n.get(C);M!==void 0&&(n.delete(C),M.dispose())}function h(){n=new WeakMap,t!==null&&(t.dispose(),t=null)}return{get:i,dispose:h}}function tl(e){let n={};function t(i){if(n[i]!==void 0)return n[i];let c;switch(i){case"WEBGL_depth_texture":c=e.getExtension("WEBGL_depth_texture")||e.getExtension("MOZ_WEBGL_depth_texture")||e.getExtension("WEBKIT_WEBGL_depth_texture");break;case"EXT_texture_filter_anisotropic":c=e.getExtension("EXT_texture_filter_anisotropic")||e.getExtension("MOZ_EXT_texture_filter_anisotropic")||e.getExtension("WEBKIT_EXT_texture_filter_anisotropic");break;case"WEBGL_compressed_texture_s3tc":c=e.getExtension("WEBGL_compressed_texture_s3tc")||e.getExtension("MOZ_WEBGL_compressed_texture_s3tc")||e.getExtension("WEBKIT_WEBGL_compressed_texture_s3tc");break;case"WEBGL_compressed_texture_pvrtc":c=e.getExtension("WEBGL_compressed_texture_pvrtc")||e.getExtension("WEBKIT_WEBGL_compressed_texture_pvrtc");break;default:c=e.getExtension(i)}return n[i]=c,c}return{has:function(i){return t(i)!==null},init:function(){t("EXT_color_buffer_float"),t("WEBGL_clip_cull_distance"),t("OES_texture_float_linear"),t("EXT_color_buffer_half_float"),t("WEBGL_multisampled_render_to_texture"),t("WEBGL_render_shared_exponent")},get:function(i){let c=t(i);return c===null&&ln("THREE.WebGLRenderer: "+i+" extension not supported."),c}}}function nl(e,n,t,i){let c={},o=new WeakMap;function h(T){let g=T.target;g.index!==null&&n.remove(g.index);for(let N in g.attributes)n.remove(g.attributes[N]);g.removeEventListener("dispose",h),delete c[g.id];let A=o.get(g);A&&(n.remove(A),o.delete(g)),i.releaseStatesOfGeometry(g),g.isInstancedBufferGeometry===!0&&delete g._maxInstanceCount,t.memory.geometries--}function d(T,g){return c[g.id]===!0||(g.addEventListener("dispose",h),c[g.id]=!0,t.memory.geometries++),g}function C(T){let g=T.attributes;for(let A in g)n.update(g[A],e.ARRAY_BUFFER)}function M(T){let g=[],A=T.index,N=T.attributes.position,L=0;if(A!==null){let U=A.array;L=A.version;for(let x=0,_=U.length;x<_;x+=3){let H=U[x+0],P=U[x+1],y=U[x+2];g.push(H,P,P,y,y,H)}}else if(N!==void 0){let U=N.array;L=N.version;for(let x=0,_=U.length/3-1;x<_;x+=3){let H=x+0,P=x+1,y=x+2;g.push(H,P,P,y,y,H)}}else return;let l=new(Wr(g)?kr:zr)(g,1);l.version=L;let r=o.get(T);r&&n.remove(r),o.set(T,l)}function D(T){let g=o.get(T);if(g){let A=T.index;A!==null&&g.version<A.version&&M(T)}else M(T);return o.get(T)}return{get:d,update:C,getWireframeAttribute:D}}function il(e,n,t){let i;function c(g){i=g}let o,h;function d(g){o=g.type,h=g.bytesPerElement}function C(g,A){e.drawElements(i,A,o,g*h),t.update(A,i,1)}function M(g,A,N){N!==0&&(e.drawElementsInstanced(i,A,o,g*h,N),t.update(A,i,N))}function D(g,A,N){if(N===0)return;n.get("WEBGL_multi_draw").multiDrawElementsWEBGL(i,A,0,o,g,0,N);let l=0;for(let r=0;r<N;r++)l+=A[r];t.update(l,i,1)}function T(g,A,N,L){if(N===0)return;let l=n.get("WEBGL_multi_draw");if(l===null)for(let r=0;r<g.length;r++)M(g[r]/h,A[r],L[r]);else{l.multiDrawElementsInstancedWEBGL(i,A,0,o,g,0,L,0,N);let r=0;for(let U=0;U<N;U++)r+=A[U]*L[U];t.update(r,i,1)}}this.setMode=c,this.setIndex=d,this.render=C,this.renderInstances=M,this.renderMultiDraw=D,this.renderMultiDrawInstances=T}function rl(e){let n={geometries:0,textures:0},t={frame:0,calls:0,triangles:0,points:0,lines:0};function i(o,h,d){switch(t.calls++,h){case e.TRIANGLES:t.triangles+=d*(o/3);break;case e.LINES:t.lines+=d*(o/2);break;case e.LINE_STRIP:t.lines+=d*(o-1);break;case e.LINE_LOOP:t.lines+=d*o;break;case e.POINTS:t.points+=d*o;break;default:console.error("THREE.WebGLInfo: Unknown draw mode:",h);break}}function c(){t.calls=0,t.triangles=0,t.points=0,t.lines=0}return{memory:n,render:t,programs:null,autoReset:!0,reset:c,update:i}}function al(e,n,t){let i=new WeakMap,c=new ft;function o(h,d,C){let M=h.morphTargetInfluences,D=d.morphAttributes.position||d.morphAttributes.normal||d.morphAttributes.color,T=D!==void 0?D.length:0,g=i.get(d);if(g===void 0||g.count!==T){let p=function(){y.dispose(),i.delete(d),d.removeEventListener("dispose",p)};g!==void 0&&g.texture.dispose();let A=d.morphAttributes.position!==void 0,N=d.morphAttributes.normal!==void 0,L=d.morphAttributes.color!==void 0,l=d.morphAttributes.position||[],r=d.morphAttributes.normal||[],U=d.morphAttributes.color||[],x=0;A===!0&&(x=1),N===!0&&(x=2),L===!0&&(x=3);let _=d.attributes.position.count*x,H=1;_>n.maxTextureSize&&(H=Math.ceil(_/n.maxTextureSize),_=n.maxTextureSize);let P=new Float32Array(_*H*4*T),y=new mr(P,_,H,T);y.type=Dt,y.needsUpdate=!0;let G=x*4;for(let f=0;f<T;f++){let R=l[f],Y=r[f],V=U[f],K=_*H*4*f;for(let J=0;J<R.count;J++){let W=J*G;A===!0&&(c.fromBufferAttribute(R,J),P[K+W+0]=c.x,P[K+W+1]=c.y,P[K+W+2]=c.z,P[K+W+3]=0),N===!0&&(c.fromBufferAttribute(Y,J),P[K+W+4]=c.x,P[K+W+5]=c.y,P[K+W+6]=c.z,P[K+W+7]=0),L===!0&&(c.fromBufferAttribute(V,J),P[K+W+8]=c.x,P[K+W+9]=c.y,P[K+W+10]=c.z,P[K+W+11]=V.itemSize===4?c.w:1)}}g={count:T,texture:y,size:new dt(_,H)},i.set(d,g),d.addEventListener("dispose",p)}if(h.isInstancedMesh===!0&&h.morphTexture!==null)C.getUniforms().setValue(e,"morphTexture",h.morphTexture,t);else{let A=0;for(let L=0;L<M.length;L++)A+=M[L];let N=d.morphTargetsRelative?1:1-A;C.getUniforms().setValue(e,"morphTargetBaseInfluence",N),C.getUniforms().setValue(e,"morphTargetInfluences",M)}C.getUniforms().setValue(e,"morphTargetsTexture",g.texture,t),C.getUniforms().setValue(e,"morphTargetsTextureSize",g.size)}return{update:o}}function ol(e,n,t,i){let c=new WeakMap;function o(C){let M=i.render.frame,D=C.geometry,T=n.get(C,D);if(c.get(T)!==M&&(n.update(T),c.set(T,M)),C.isInstancedMesh&&(C.hasEventListener("dispose",d)===!1&&C.addEventListener("dispose",d),c.get(C)!==M&&(t.update(C.instanceMatrix,e.ARRAY_BUFFER),C.instanceColor!==null&&t.update(C.instanceColor,e.ARRAY_BUFFER),c.set(C,M))),C.isSkinnedMesh){let g=C.skeleton;c.get(g)!==M&&(g.update(),c.set(g,M))}return T}function h(){c=new WeakMap}function d(C){let M=C.target;M.removeEventListener("dispose",d),t.remove(M.instanceMatrix),M.instanceColor!==null&&t.remove(M.instanceColor)}return{update:o,dispose:h}}var Pr=new gr,Xi=new vr(1,1),Lr=new mr,Ur=new Kr,Dr=new Xr,Ki=[],Yi=[],qi=new Float32Array(16),$i=new Float32Array(9),Zi=new Float32Array(4);function Wt(e,n,t){let i=e[0];if(i<=0||i>0)return e;let c=n*t,o=Ki[c];if(o===void 0&&(o=new Float32Array(c),Ki[c]=o),n!==0){i.toArray(o,0);for(let h=1,d=0;h!==n;++h)d+=t,e[h].toArray(o,d)}return o}function it(e,n){if(e.length!==n.length)return!1;for(let t=0,i=e.length;t<i;t++)if(e[t]!==n[t])return!1;return!0}function rt(e,n){for(let t=0,i=n.length;t<i;t++)e[t]=n[t]}function gn(e,n){let t=Yi[n];t===void 0&&(t=new Int32Array(n),Yi[n]=t);for(let i=0;i!==n;++i)t[i]=e.allocateTextureUnit();return t}function sl(e,n){let t=this.cache;t[0]!==n&&(e.uniform1f(this.addr,n),t[0]=n)}function cl(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y)&&(e.uniform2f(this.addr,n.x,n.y),t[0]=n.x,t[1]=n.y);else{if(it(t,n))return;e.uniform2fv(this.addr,n),rt(t,n)}}function ll(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y||t[2]!==n.z)&&(e.uniform3f(this.addr,n.x,n.y,n.z),t[0]=n.x,t[1]=n.y,t[2]=n.z);else if(n.r!==void 0)(t[0]!==n.r||t[1]!==n.g||t[2]!==n.b)&&(e.uniform3f(this.addr,n.r,n.g,n.b),t[0]=n.r,t[1]=n.g,t[2]=n.b);else{if(it(t,n))return;e.uniform3fv(this.addr,n),rt(t,n)}}function fl(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y||t[2]!==n.z||t[3]!==n.w)&&(e.uniform4f(this.addr,n.x,n.y,n.z,n.w),t[0]=n.x,t[1]=n.y,t[2]=n.z,t[3]=n.w);else{if(it(t,n))return;e.uniform4fv(this.addr,n),rt(t,n)}}function dl(e,n){let t=this.cache,i=n.elements;if(i===void 0){if(it(t,n))return;e.uniformMatrix2fv(this.addr,!1,n),rt(t,n)}else{if(it(t,i))return;Zi.set(i),e.uniformMatrix2fv(this.addr,!1,Zi),rt(t,i)}}function ul(e,n){let t=this.cache,i=n.elements;if(i===void 0){if(it(t,n))return;e.uniformMatrix3fv(this.addr,!1,n),rt(t,n)}else{if(it(t,i))return;$i.set(i),e.uniformMatrix3fv(this.addr,!1,$i),rt(t,i)}}function pl(e,n){let t=this.cache,i=n.elements;if(i===void 0){if(it(t,n))return;e.uniformMatrix4fv(this.addr,!1,n),rt(t,n)}else{if(it(t,i))return;qi.set(i),e.uniformMatrix4fv(this.addr,!1,qi),rt(t,i)}}function hl(e,n){let t=this.cache;t[0]!==n&&(e.uniform1i(this.addr,n),t[0]=n)}function ml(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y)&&(e.uniform2i(this.addr,n.x,n.y),t[0]=n.x,t[1]=n.y);else{if(it(t,n))return;e.uniform2iv(this.addr,n),rt(t,n)}}function _l(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y||t[2]!==n.z)&&(e.uniform3i(this.addr,n.x,n.y,n.z),t[0]=n.x,t[1]=n.y,t[2]=n.z);else{if(it(t,n))return;e.uniform3iv(this.addr,n),rt(t,n)}}function vl(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y||t[2]!==n.z||t[3]!==n.w)&&(e.uniform4i(this.addr,n.x,n.y,n.z,n.w),t[0]=n.x,t[1]=n.y,t[2]=n.z,t[3]=n.w);else{if(it(t,n))return;e.uniform4iv(this.addr,n),rt(t,n)}}function gl(e,n){let t=this.cache;t[0]!==n&&(e.uniform1ui(this.addr,n),t[0]=n)}function Sl(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y)&&(e.uniform2ui(this.addr,n.x,n.y),t[0]=n.x,t[1]=n.y);else{if(it(t,n))return;e.uniform2uiv(this.addr,n),rt(t,n)}}function El(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y||t[2]!==n.z)&&(e.uniform3ui(this.addr,n.x,n.y,n.z),t[0]=n.x,t[1]=n.y,t[2]=n.z);else{if(it(t,n))return;e.uniform3uiv(this.addr,n),rt(t,n)}}function Ml(e,n){let t=this.cache;if(n.x!==void 0)(t[0]!==n.x||t[1]!==n.y||t[2]!==n.z||t[3]!==n.w)&&(e.uniform4ui(this.addr,n.x,n.y,n.z,n.w),t[0]=n.x,t[1]=n.y,t[2]=n.z,t[3]=n.w);else{if(it(t,n))return;e.uniform4uiv(this.addr,n),rt(t,n)}}function Tl(e,n,t){let i=this.cache,c=t.allocateTextureUnit();i[0]!==c&&(e.uniform1i(this.addr,c),i[0]=c);let o;this.type===e.SAMPLER_2D_SHADOW?(Xi.compareFunction=_r,o=Xi):o=Pr,t.setTexture2D(n||o,c)}function xl(e,n,t){let i=this.cache,c=t.allocateTextureUnit();i[0]!==c&&(e.uniform1i(this.addr,c),i[0]=c),t.setTexture3D(n||Ur,c)}function Al(e,n,t){let i=this.cache,c=t.allocateTextureUnit();i[0]!==c&&(e.uniform1i(this.addr,c),i[0]=c),t.setTextureCube(n||Dr,c)}function Rl(e,n,t){let i=this.cache,c=t.allocateTextureUnit();i[0]!==c&&(e.uniform1i(this.addr,c),i[0]=c),t.setTexture2DArray(n||Lr,c)}function Cl(e){switch(e){case 5126:return sl;case 35664:return cl;case 35665:return ll;case 35666:return fl;case 35674:return dl;case 35675:return ul;case 35676:return pl;case 5124:case 35670:return hl;case 35667:case 35671:return ml;case 35668:case 35672:return _l;case 35669:case 35673:return vl;case 5125:return gl;case 36294:return Sl;case 36295:return El;case 36296:return Ml;case 35678:case 36198:case 36298:case 36306:case 35682:return Tl;case 35679:case 36299:case 36307:return xl;case 35680:case 36300:case 36308:case 36293:return Al;case 36289:case 36303:case 36311:case 36292:return Rl}}function bl(e,n){e.uniform1fv(this.addr,n)}function Pl(e,n){let t=Wt(n,this.size,2);e.uniform2fv(this.addr,t)}function Ll(e,n){let t=Wt(n,this.size,3);e.uniform3fv(this.addr,t)}function Ul(e,n){let t=Wt(n,this.size,4);e.uniform4fv(this.addr,t)}function Dl(e,n){let t=Wt(n,this.size,4);e.uniformMatrix2fv(this.addr,!1,t)}function wl(e,n){let t=Wt(n,this.size,9);e.uniformMatrix3fv(this.addr,!1,t)}function Il(e,n){let t=Wt(n,this.size,16);e.uniformMatrix4fv(this.addr,!1,t)}function yl(e,n){e.uniform1iv(this.addr,n)}function Nl(e,n){e.uniform2iv(this.addr,n)}function Ol(e,n){e.uniform3iv(this.addr,n)}function Fl(e,n){e.uniform4iv(this.addr,n)}function Bl(e,n){e.uniform1uiv(this.addr,n)}function Gl(e,n){e.uniform2uiv(this.addr,n)}function Hl(e,n){e.uniform3uiv(this.addr,n)}function Vl(e,n){e.uniform4uiv(this.addr,n)}function kl(e,n,t){let i=this.cache,c=n.length,o=gn(t,c);it(i,o)||(e.uniform1iv(this.addr,o),rt(i,o));for(let h=0;h!==c;++h)t.setTexture2D(n[h]||Pr,o[h])}function zl(e,n,t){let i=this.cache,c=n.length,o=gn(t,c);it(i,o)||(e.uniform1iv(this.addr,o),rt(i,o));for(let h=0;h!==c;++h)t.setTexture3D(n[h]||Ur,o[h])}function Wl(e,n,t){let i=this.cache,c=n.length,o=gn(t,c);it(i,o)||(e.uniform1iv(this.addr,o),rt(i,o));for(let h=0;h!==c;++h)t.setTextureCube(n[h]||Dr,o[h])}function Xl(e,n,t){let i=this.cache,c=n.length,o=gn(t,c);it(i,o)||(e.uniform1iv(this.addr,o),rt(i,o));for(let h=0;h!==c;++h)t.setTexture2DArray(n[h]||Lr,o[h])}function Kl(e){switch(e){case 5126:return bl;case 35664:return Pl;case 35665:return Ll;case 35666:return Ul;case 35674:return Dl;case 35675:return wl;case 35676:return Il;case 5124:case 35670:return yl;case 35667:case 35671:return Nl;case 35668:case 35672:return Ol;case 35669:case 35673:return Fl;case 5125:return Bl;case 36294:return Gl;case 36295:return Hl;case 36296:return Vl;case 35678:case 36198:case 36298:case 36306:case 35682:return kl;case 35679:case 36299:case 36307:return zl;case 35680:case 36300:case 36308:case 36293:return Wl;case 36289:case 36303:case 36311:case 36292:return Xl}}var zn=class{constructor(n,t,i){this.id=n,this.addr=i,this.cache=[],this.type=t.type,this.setValue=Cl(t.type)}},Wn=class{constructor(n,t,i){this.id=n,this.addr=i,this.cache=[],this.type=t.type,this.size=t.size,this.setValue=Kl(t.type)}},Xn=class{constructor(n){this.id=n,this.seq=[],this.map={}}setValue(n,t,i){let c=this.seq;for(let o=0,h=c.length;o!==h;++o){let d=c[o];d.setValue(n,t[d.id],i)}}},In=/(\w+)(\])?(\[|\.)?/g;function Qi(e,n){e.seq.push(n),e.map[n.id]=n}function Yl(e,n,t){let i=e.name,c=i.length;for(In.lastIndex=0;;){let o=In.exec(i),h=In.lastIndex,d=o[1],C=o[2]==="]",M=o[3];if(C&&(d=d|0),M===void 0||M==="["&&h+2===c){Qi(t,M===void 0?new zn(d,e,n):new Wn(d,e,n));break}else{let T=t.map[d];T===void 0&&(T=new Xn(d),Qi(t,T)),t=T}}}var Ht=class{constructor(n,t){this.seq=[],this.map={};let i=n.getProgramParameter(t,n.ACTIVE_UNIFORMS);for(let c=0;c<i;++c){let o=n.getActiveUniform(t,c),h=n.getUniformLocation(t,o.name);Yl(o,h,this)}}setValue(n,t,i,c){let o=this.map[t];o!==void 0&&o.setValue(n,i,c)}setOptional(n,t,i){let c=t[i];c!==void 0&&this.setValue(n,i,c)}static upload(n,t,i,c){for(let o=0,h=t.length;o!==h;++o){let d=t[o],C=i[d.id];C.needsUpdate!==!1&&d.setValue(n,C.value,c)}}static seqWithValue(n,t){let i=[];for(let c=0,o=n.length;c!==o;++c){let h=n[c];h.id in t&&i.push(h)}return i}};function Ji(e,n,t){let i=e.createShader(n);return e.shaderSource(i,t),e.compileShader(i),i}var ql=37297,$l=0;function Zl(e,n){let t=e.split(`
`),i=[],c=Math.max(n-6,0),o=Math.min(n+6,t.length);for(let h=c;h<o;h++){let d=h+1;i.push(`${d===n?">":" "} ${d}: ${t[h]}`)}return i.join(`
`)}var ji=new Oe;function Ql(e){tt._getMatrix(ji,tt.workingColorSpace,e);let n=`mat3( ${ji.elements.map(t=>t.toFixed(4))} )`;switch(tt.getTransfer(e)){case Er:return[n,"LinearTransferOETF"];case Ye:return[n,"sRGBTransferOETF"];default:return console.warn("THREE.WebGLProgram: Unsupported color space: ",e),[n,"LinearTransferOETF"]}}function er(e,n,t){let i=e.getShaderParameter(n,e.COMPILE_STATUS),c=e.getShaderInfoLog(n).trim();if(i&&c==="")return"";let o=/ERROR: 0:(\d+)/.exec(c);if(o){let h=parseInt(o[1]);return t.toUpperCase()+`

`+c+`

`+Zl(e.getShaderSource(n),h)}else return c}function Jl(e,n){let t=Ql(n);return[`vec4 ${e}( vec4 value ) {`,`	return ${t[1]}( vec4( value.rgb * ${t[0]}, value.a ) );`,"}"].join(`
`)}function jl(e,n){let t;switch(n){case ea:t="Linear";break;case jr:t="Reinhard";break;case Jr:t="Cineon";break;case Qr:t="ACESFilmic";break;case Zr:t="AgX";break;case $r:t="Neutral";break;case qr:t="Custom";break;default:console.warn("THREE.WebGLProgram: Unsupported toneMapping:",n),t="Linear"}return"vec3 "+e+"( vec3 color ) { return "+t+"ToneMapping( color ); }"}var on=new We;function ef(){tt.getLuminanceCoefficients(on);let e=on.x.toFixed(4),n=on.y.toFixed(4),t=on.z.toFixed(4);return["float luminance( const in vec3 rgb ) {",`	const vec3 weights = vec3( ${e}, ${n}, ${t} );`,"	return dot( weights, rgb );","}"].join(`
`)}function tf(e){return[e.extensionClipCullDistance?"#extension GL_ANGLE_clip_cull_distance : require":"",e.extensionMultiDraw?"#extension GL_ANGLE_multi_draw : require":""].filter(qt).join(`
`)}function nf(e){let n=[];for(let t in e){let i=e[t];i!==!1&&n.push("#define "+t+" "+i)}return n.join(`
`)}function rf(e,n){let t={},i=e.getProgramParameter(n,e.ACTIVE_ATTRIBUTES);for(let c=0;c<i;c++){let o=e.getActiveAttrib(n,c),h=o.name,d=1;o.type===e.FLOAT_MAT2&&(d=2),o.type===e.FLOAT_MAT3&&(d=3),o.type===e.FLOAT_MAT4&&(d=4),t[h]={type:o.type,location:e.getAttribLocation(n,h),locationSize:d}}return t}function qt(e){return e!==""}function tr(e,n){let t=n.numSpotLightShadows+n.numSpotLightMaps-n.numSpotLightShadowsWithMaps;return e.replace(/NUM_DIR_LIGHTS/g,n.numDirLights).replace(/NUM_SPOT_LIGHTS/g,n.numSpotLights).replace(/NUM_SPOT_LIGHT_MAPS/g,n.numSpotLightMaps).replace(/NUM_SPOT_LIGHT_COORDS/g,t).replace(/NUM_RECT_AREA_LIGHTS/g,n.numRectAreaLights).replace(/NUM_POINT_LIGHTS/g,n.numPointLights).replace(/NUM_HEMI_LIGHTS/g,n.numHemiLights).replace(/NUM_DIR_LIGHT_SHADOWS/g,n.numDirLightShadows).replace(/NUM_SPOT_LIGHT_SHADOWS_WITH_MAPS/g,n.numSpotLightShadowsWithMaps).replace(/NUM_SPOT_LIGHT_SHADOWS/g,n.numSpotLightShadows).replace(/NUM_POINT_LIGHT_SHADOWS/g,n.numPointLightShadows)}function nr(e,n){return e.replace(/NUM_CLIPPING_PLANES/g,n.numClippingPlanes).replace(/UNION_CLIPPING_PLANES/g,n.numClippingPlanes-n.numClipIntersection)}var af=/^[ \t]*#include +<([\w\d./]+)>/gm;function Kn(e){return e.replace(af,sf)}var of=new Map;function sf(e,n){let t=De[n];if(t===void 0){let i=of.get(n);if(i!==void 0)t=De[i],console.warn('THREE.WebGLRenderer: Shader chunk "%s" has been deprecated. Use "%s" instead.',n,i);else throw new Error("Can not resolve #include <"+n+">")}return Kn(t)}var cf=/#pragma unroll_loop_start\s+for\s*\(\s*int\s+i\s*=\s*(\d+)\s*;\s*i\s*<\s*(\d+)\s*;\s*i\s*\+\+\s*\)\s*{([\s\S]+?)}\s+#pragma unroll_loop_end/g;function ir(e){return e.replace(cf,lf)}function lf(e,n,t,i){let c="";for(let o=parseInt(n);o<parseInt(t);o++)c+=i.replace(/\[\s*i\s*\]/g,"[ "+o+" ]").replace(/UNROLLED_LOOP_INDEX/g,o);return c}function rr(e){let n=`precision ${e.precision} float;
	precision ${e.precision} int;
	precision ${e.precision} sampler2D;
	precision ${e.precision} samplerCube;
	precision ${e.precision} sampler3D;
	precision ${e.precision} sampler2DArray;
	precision ${e.precision} sampler2DShadow;
	precision ${e.precision} samplerCubeShadow;
	precision ${e.precision} sampler2DArrayShadow;
	precision ${e.precision} isampler2D;
	precision ${e.precision} isampler3D;
	precision ${e.precision} isamplerCube;
	precision ${e.precision} isampler2DArray;
	precision ${e.precision} usampler2D;
	precision ${e.precision} usampler3D;
	precision ${e.precision} usamplerCube;
	precision ${e.precision} usampler2DArray;
	`;return e.precision==="highp"?n+=`
#define HIGH_PRECISION`:e.precision==="mediump"?n+=`
#define MEDIUM_PRECISION`:e.precision==="lowp"&&(n+=`
#define LOW_PRECISION`),n}function ff(e){let n="SHADOWMAP_TYPE_BASIC";return e.shadowMapType===Sr?n="SHADOWMAP_TYPE_PCF":e.shadowMapType===Yr?n="SHADOWMAP_TYPE_PCF_SOFT":e.shadowMapType===Et&&(n="SHADOWMAP_TYPE_VSM"),n}function df(e){let n="ENVMAP_TYPE_CUBE";if(e.envMap)switch(e.envMapMode){case Qt:case kt:n="ENVMAP_TYPE_CUBE";break;case mn:n="ENVMAP_TYPE_CUBE_UV";break}return n}function uf(e){let n="ENVMAP_MODE_REFLECTION";if(e.envMap)switch(e.envMapMode){case kt:n="ENVMAP_MODE_REFRACTION";break}return n}function pf(e){let n="ENVMAP_BLENDING_NONE";if(e.envMap)switch(e.combine){case ia:n="ENVMAP_BLENDING_MULTIPLY";break;case na:n="ENVMAP_BLENDING_MIX";break;case ta:n="ENVMAP_BLENDING_ADD";break}return n}function hf(e){let n=e.envMapCubeUVHeight;if(n===null)return null;let t=Math.log2(n)-2,i=1/n;return{texelWidth:1/(3*Math.max(Math.pow(2,t),112)),texelHeight:i,maxMip:t}}function mf(e,n,t,i){let c=e.getContext(),o=t.defines,h=t.vertexShader,d=t.fragmentShader,C=ff(t),M=df(t),D=uf(t),T=pf(t),g=hf(t),A=tf(t),N=nf(o),L=c.createProgram(),l,r,U=t.glslVersion?"#version "+t.glslVersion+`
`:"";t.isRawShaderMaterial?(l=["#define SHADER_TYPE "+t.shaderType,"#define SHADER_NAME "+t.shaderName,N].filter(qt).join(`
`),l.length>0&&(l+=`
`),r=["#define SHADER_TYPE "+t.shaderType,"#define SHADER_NAME "+t.shaderName,N].filter(qt).join(`
`),r.length>0&&(r+=`
`)):(l=[rr(t),"#define SHADER_TYPE "+t.shaderType,"#define SHADER_NAME "+t.shaderName,N,t.extensionClipCullDistance?"#define USE_CLIP_DISTANCE":"",t.batching?"#define USE_BATCHING":"",t.batchingColor?"#define USE_BATCHING_COLOR":"",t.instancing?"#define USE_INSTANCING":"",t.instancingColor?"#define USE_INSTANCING_COLOR":"",t.instancingMorph?"#define USE_INSTANCING_MORPH":"",t.useFog&&t.fog?"#define USE_FOG":"",t.useFog&&t.fogExp2?"#define FOG_EXP2":"",t.map?"#define USE_MAP":"",t.envMap?"#define USE_ENVMAP":"",t.envMap?"#define "+D:"",t.lightMap?"#define USE_LIGHTMAP":"",t.aoMap?"#define USE_AOMAP":"",t.bumpMap?"#define USE_BUMPMAP":"",t.normalMap?"#define USE_NORMALMAP":"",t.normalMapObjectSpace?"#define USE_NORMALMAP_OBJECTSPACE":"",t.normalMapTangentSpace?"#define USE_NORMALMAP_TANGENTSPACE":"",t.displacementMap?"#define USE_DISPLACEMENTMAP":"",t.emissiveMap?"#define USE_EMISSIVEMAP":"",t.anisotropy?"#define USE_ANISOTROPY":"",t.anisotropyMap?"#define USE_ANISOTROPYMAP":"",t.clearcoatMap?"#define USE_CLEARCOATMAP":"",t.clearcoatRoughnessMap?"#define USE_CLEARCOAT_ROUGHNESSMAP":"",t.clearcoatNormalMap?"#define USE_CLEARCOAT_NORMALMAP":"",t.iridescenceMap?"#define USE_IRIDESCENCEMAP":"",t.iridescenceThicknessMap?"#define USE_IRIDESCENCE_THICKNESSMAP":"",t.specularMap?"#define USE_SPECULARMAP":"",t.specularColorMap?"#define USE_SPECULAR_COLORMAP":"",t.specularIntensityMap?"#define USE_SPECULAR_INTENSITYMAP":"",t.roughnessMap?"#define USE_ROUGHNESSMAP":"",t.metalnessMap?"#define USE_METALNESSMAP":"",t.alphaMap?"#define USE_ALPHAMAP":"",t.alphaHash?"#define USE_ALPHAHASH":"",t.transmission?"#define USE_TRANSMISSION":"",t.transmissionMap?"#define USE_TRANSMISSIONMAP":"",t.thicknessMap?"#define USE_THICKNESSMAP":"",t.sheenColorMap?"#define USE_SHEEN_COLORMAP":"",t.sheenRoughnessMap?"#define USE_SHEEN_ROUGHNESSMAP":"",t.mapUv?"#define MAP_UV "+t.mapUv:"",t.alphaMapUv?"#define ALPHAMAP_UV "+t.alphaMapUv:"",t.lightMapUv?"#define LIGHTMAP_UV "+t.lightMapUv:"",t.aoMapUv?"#define AOMAP_UV "+t.aoMapUv:"",t.emissiveMapUv?"#define EMISSIVEMAP_UV "+t.emissiveMapUv:"",t.bumpMapUv?"#define BUMPMAP_UV "+t.bumpMapUv:"",t.normalMapUv?"#define NORMALMAP_UV "+t.normalMapUv:"",t.displacementMapUv?"#define DISPLACEMENTMAP_UV "+t.displacementMapUv:"",t.metalnessMapUv?"#define METALNESSMAP_UV "+t.metalnessMapUv:"",t.roughnessMapUv?"#define ROUGHNESSMAP_UV "+t.roughnessMapUv:"",t.anisotropyMapUv?"#define ANISOTROPYMAP_UV "+t.anisotropyMapUv:"",t.clearcoatMapUv?"#define CLEARCOATMAP_UV "+t.clearcoatMapUv:"",t.clearcoatNormalMapUv?"#define CLEARCOAT_NORMALMAP_UV "+t.clearcoatNormalMapUv:"",t.clearcoatRoughnessMapUv?"#define CLEARCOAT_ROUGHNESSMAP_UV "+t.clearcoatRoughnessMapUv:"",t.iridescenceMapUv?"#define IRIDESCENCEMAP_UV "+t.iridescenceMapUv:"",t.iridescenceThicknessMapUv?"#define IRIDESCENCE_THICKNESSMAP_UV "+t.iridescenceThicknessMapUv:"",t.sheenColorMapUv?"#define SHEEN_COLORMAP_UV "+t.sheenColorMapUv:"",t.sheenRoughnessMapUv?"#define SHEEN_ROUGHNESSMAP_UV "+t.sheenRoughnessMapUv:"",t.specularMapUv?"#define SPECULARMAP_UV "+t.specularMapUv:"",t.specularColorMapUv?"#define SPECULAR_COLORMAP_UV "+t.specularColorMapUv:"",t.specularIntensityMapUv?"#define SPECULAR_INTENSITYMAP_UV "+t.specularIntensityMapUv:"",t.transmissionMapUv?"#define TRANSMISSIONMAP_UV "+t.transmissionMapUv:"",t.thicknessMapUv?"#define THICKNESSMAP_UV "+t.thicknessMapUv:"",t.vertexTangents&&t.flatShading===!1?"#define USE_TANGENT":"",t.vertexColors?"#define USE_COLOR":"",t.vertexAlphas?"#define USE_COLOR_ALPHA":"",t.vertexUv1s?"#define USE_UV1":"",t.vertexUv2s?"#define USE_UV2":"",t.vertexUv3s?"#define USE_UV3":"",t.pointsUvs?"#define USE_POINTS_UV":"",t.flatShading?"#define FLAT_SHADED":"",t.skinning?"#define USE_SKINNING":"",t.morphTargets?"#define USE_MORPHTARGETS":"",t.morphNormals&&t.flatShading===!1?"#define USE_MORPHNORMALS":"",t.morphColors?"#define USE_MORPHCOLORS":"",t.morphTargetsCount>0?"#define MORPHTARGETS_TEXTURE_STRIDE "+t.morphTextureStride:"",t.morphTargetsCount>0?"#define MORPHTARGETS_COUNT "+t.morphTargetsCount:"",t.doubleSided?"#define DOUBLE_SIDED":"",t.flipSided?"#define FLIP_SIDED":"",t.shadowMapEnabled?"#define USE_SHADOWMAP":"",t.shadowMapEnabled?"#define "+C:"",t.sizeAttenuation?"#define USE_SIZEATTENUATION":"",t.numLightProbes>0?"#define USE_LIGHT_PROBES":"",t.logarithmicDepthBuffer?"#define USE_LOGDEPTHBUF":"",t.reverseDepthBuffer?"#define USE_REVERSEDEPTHBUF":"","uniform mat4 modelMatrix;","uniform mat4 modelViewMatrix;","uniform mat4 projectionMatrix;","uniform mat4 viewMatrix;","uniform mat3 normalMatrix;","uniform vec3 cameraPosition;","uniform bool isOrthographic;","#ifdef USE_INSTANCING","	attribute mat4 instanceMatrix;","#endif","#ifdef USE_INSTANCING_COLOR","	attribute vec3 instanceColor;","#endif","#ifdef USE_INSTANCING_MORPH","	uniform sampler2D morphTexture;","#endif","attribute vec3 position;","attribute vec3 normal;","attribute vec2 uv;","#ifdef USE_UV1","	attribute vec2 uv1;","#endif","#ifdef USE_UV2","	attribute vec2 uv2;","#endif","#ifdef USE_UV3","	attribute vec2 uv3;","#endif","#ifdef USE_TANGENT","	attribute vec4 tangent;","#endif","#if defined( USE_COLOR_ALPHA )","	attribute vec4 color;","#elif defined( USE_COLOR )","	attribute vec3 color;","#endif","#ifdef USE_SKINNING","	attribute vec4 skinIndex;","	attribute vec4 skinWeight;","#endif",`
`].filter(qt).join(`
`),r=[rr(t),"#define SHADER_TYPE "+t.shaderType,"#define SHADER_NAME "+t.shaderName,N,t.useFog&&t.fog?"#define USE_FOG":"",t.useFog&&t.fogExp2?"#define FOG_EXP2":"",t.alphaToCoverage?"#define ALPHA_TO_COVERAGE":"",t.map?"#define USE_MAP":"",t.matcap?"#define USE_MATCAP":"",t.envMap?"#define USE_ENVMAP":"",t.envMap?"#define "+M:"",t.envMap?"#define "+D:"",t.envMap?"#define "+T:"",g?"#define CUBEUV_TEXEL_WIDTH "+g.texelWidth:"",g?"#define CUBEUV_TEXEL_HEIGHT "+g.texelHeight:"",g?"#define CUBEUV_MAX_MIP "+g.maxMip+".0":"",t.lightMap?"#define USE_LIGHTMAP":"",t.aoMap?"#define USE_AOMAP":"",t.bumpMap?"#define USE_BUMPMAP":"",t.normalMap?"#define USE_NORMALMAP":"",t.normalMapObjectSpace?"#define USE_NORMALMAP_OBJECTSPACE":"",t.normalMapTangentSpace?"#define USE_NORMALMAP_TANGENTSPACE":"",t.emissiveMap?"#define USE_EMISSIVEMAP":"",t.anisotropy?"#define USE_ANISOTROPY":"",t.anisotropyMap?"#define USE_ANISOTROPYMAP":"",t.clearcoat?"#define USE_CLEARCOAT":"",t.clearcoatMap?"#define USE_CLEARCOATMAP":"",t.clearcoatRoughnessMap?"#define USE_CLEARCOAT_ROUGHNESSMAP":"",t.clearcoatNormalMap?"#define USE_CLEARCOAT_NORMALMAP":"",t.dispersion?"#define USE_DISPERSION":"",t.iridescence?"#define USE_IRIDESCENCE":"",t.iridescenceMap?"#define USE_IRIDESCENCEMAP":"",t.iridescenceThicknessMap?"#define USE_IRIDESCENCE_THICKNESSMAP":"",t.specularMap?"#define USE_SPECULARMAP":"",t.specularColorMap?"#define USE_SPECULAR_COLORMAP":"",t.specularIntensityMap?"#define USE_SPECULAR_INTENSITYMAP":"",t.roughnessMap?"#define USE_ROUGHNESSMAP":"",t.metalnessMap?"#define USE_METALNESSMAP":"",t.alphaMap?"#define USE_ALPHAMAP":"",t.alphaTest?"#define USE_ALPHATEST":"",t.alphaHash?"#define USE_ALPHAHASH":"",t.sheen?"#define USE_SHEEN":"",t.sheenColorMap?"#define USE_SHEEN_COLORMAP":"",t.sheenRoughnessMap?"#define USE_SHEEN_ROUGHNESSMAP":"",t.transmission?"#define USE_TRANSMISSION":"",t.transmissionMap?"#define USE_TRANSMISSIONMAP":"",t.thicknessMap?"#define USE_THICKNESSMAP":"",t.vertexTangents&&t.flatShading===!1?"#define USE_TANGENT":"",t.vertexColors||t.instancingColor||t.batchingColor?"#define USE_COLOR":"",t.vertexAlphas?"#define USE_COLOR_ALPHA":"",t.vertexUv1s?"#define USE_UV1":"",t.vertexUv2s?"#define USE_UV2":"",t.vertexUv3s?"#define USE_UV3":"",t.pointsUvs?"#define USE_POINTS_UV":"",t.gradientMap?"#define USE_GRADIENTMAP":"",t.flatShading?"#define FLAT_SHADED":"",t.doubleSided?"#define DOUBLE_SIDED":"",t.flipSided?"#define FLIP_SIDED":"",t.shadowMapEnabled?"#define USE_SHADOWMAP":"",t.shadowMapEnabled?"#define "+C:"",t.premultipliedAlpha?"#define PREMULTIPLIED_ALPHA":"",t.numLightProbes>0?"#define USE_LIGHT_PROBES":"",t.decodeVideoTexture?"#define DECODE_VIDEO_TEXTURE":"",t.decodeVideoTextureEmissive?"#define DECODE_VIDEO_TEXTURE_EMISSIVE":"",t.logarithmicDepthBuffer?"#define USE_LOGDEPTHBUF":"",t.reverseDepthBuffer?"#define USE_REVERSEDEPTHBUF":"","uniform mat4 viewMatrix;","uniform vec3 cameraPosition;","uniform bool isOrthographic;",t.toneMapping!==At?"#define TONE_MAPPING":"",t.toneMapping!==At?De.tonemapping_pars_fragment:"",t.toneMapping!==At?jl("toneMapping",t.toneMapping):"",t.dithering?"#define DITHERING":"",t.opaque?"#define OPAQUE":"",De.colorspace_pars_fragment,Jl("linearToOutputTexel",t.outputColorSpace),ef(),t.useDepthPacking?"#define DEPTH_PACKING "+t.depthPacking:"",`
`].filter(qt).join(`
`)),h=Kn(h),h=tr(h,t),h=nr(h,t),d=Kn(d),d=tr(d,t),d=nr(d,t),h=ir(h),d=ir(d),t.isRawShaderMaterial!==!0&&(U=`#version 300 es
`,l=[A,"#define attribute in","#define varying out","#define texture2D texture"].join(`
`)+`
`+l,r=["#define varying in",t.glslVersion===si?"":"layout(location = 0) out highp vec4 pc_fragColor;",t.glslVersion===si?"":"#define gl_FragColor pc_fragColor","#define gl_FragDepthEXT gl_FragDepth","#define texture2D texture","#define textureCube texture","#define texture2DProj textureProj","#define texture2DLodEXT textureLod","#define texture2DProjLodEXT textureProjLod","#define textureCubeLodEXT textureLod","#define texture2DGradEXT textureGrad","#define texture2DProjGradEXT textureProjGrad","#define textureCubeGradEXT textureGrad"].join(`
`)+`
`+r);let x=U+l+h,_=U+r+d,H=Ji(c,c.VERTEX_SHADER,x),P=Ji(c,c.FRAGMENT_SHADER,_);c.attachShader(L,H),c.attachShader(L,P),t.index0AttributeName!==void 0?c.bindAttribLocation(L,0,t.index0AttributeName):t.morphTargets===!0&&c.bindAttribLocation(L,0,"position"),c.linkProgram(L);function y(R){if(e.debug.checkShaderErrors){let Y=c.getProgramInfoLog(L).trim(),V=c.getShaderInfoLog(H).trim(),K=c.getShaderInfoLog(P).trim(),J=!0,W=!0;if(c.getProgramParameter(L,c.LINK_STATUS)===!1)if(J=!1,typeof e.debug.onShaderError=="function")e.debug.onShaderError(c,L,H,P);else{let ee=er(c,H,"vertex"),F=er(c,P,"fragment");console.error("THREE.WebGLProgram: Shader Error "+c.getError()+" - VALIDATE_STATUS "+c.getProgramParameter(L,c.VALIDATE_STATUS)+`

Material Name: `+R.name+`
Material Type: `+R.type+`

Program Info Log: `+Y+`
`+ee+`
`+F)}else Y!==""?console.warn("THREE.WebGLProgram: Program Info Log:",Y):(V===""||K==="")&&(W=!1);W&&(R.diagnostics={runnable:J,programLog:Y,vertexShader:{log:V,prefix:l},fragmentShader:{log:K,prefix:r}})}c.deleteShader(H),c.deleteShader(P),G=new Ht(c,L),p=rf(c,L)}let G;this.getUniforms=function(){return G===void 0&&y(this),G};let p;this.getAttributes=function(){return p===void 0&&y(this),p};let f=t.rendererExtensionParallelShaderCompile===!1;return this.isReady=function(){return f===!1&&(f=c.getProgramParameter(L,ql)),f},this.destroy=function(){i.releaseStatesOfProgram(this),c.deleteProgram(L),this.program=void 0},this.type=t.shaderType,this.name=t.shaderName,this.id=$l++,this.cacheKey=n,this.usedTimes=1,this.program=L,this.vertexShader=H,this.fragmentShader=P,this}var _f=0,Yn=class{constructor(){this.shaderCache=new Map,this.materialCache=new Map}update(n){let t=n.vertexShader,i=n.fragmentShader,c=this._getShaderStage(t),o=this._getShaderStage(i),h=this._getShaderCacheForMaterial(n);return h.has(c)===!1&&(h.add(c),c.usedTimes++),h.has(o)===!1&&(h.add(o),o.usedTimes++),this}remove(n){let t=this.materialCache.get(n);for(let i of t)i.usedTimes--,i.usedTimes===0&&this.shaderCache.delete(i.code);return this.materialCache.delete(n),this}getVertexShaderID(n){return this._getShaderStage(n.vertexShader).id}getFragmentShaderID(n){return this._getShaderStage(n.fragmentShader).id}dispose(){this.shaderCache.clear(),this.materialCache.clear()}_getShaderCacheForMaterial(n){let t=this.materialCache,i=t.get(n);return i===void 0&&(i=new Set,t.set(n,i)),i}_getShaderStage(n){let t=this.shaderCache,i=t.get(n);return i===void 0&&(i=new qn(n),t.set(n,i)),i}},qn=class{constructor(n){this.id=_f++,this.code=n,this.usedTimes=0}};function vf(e,n,t,i,c,o,h){let d=new sa,C=new Yn,M=new Set,D=[],T=c.logarithmicDepthBuffer,g=c.vertexTextures,A=c.precision,N={MeshDepthMaterial:"depth",MeshDistanceMaterial:"distanceRGBA",MeshNormalMaterial:"normal",MeshBasicMaterial:"basic",MeshLambertMaterial:"lambert",MeshPhongMaterial:"phong",MeshToonMaterial:"toon",MeshStandardMaterial:"physical",MeshPhysicalMaterial:"physical",MeshMatcapMaterial:"matcap",LineBasicMaterial:"basic",LineDashedMaterial:"dashed",PointsMaterial:"points",ShadowMaterial:"shadow",SpriteMaterial:"sprite"};function L(p){return M.add(p),p===0?"uv":`uv${p}`}function l(p,f,R,Y,V){let K=Y.fog,J=V.geometry,W=p.isMeshStandardMaterial?Y.environment:null,ee=(p.isMeshStandardMaterial?t:n).get(p.envMap||W),F=ee&&ee.mapping===mn?ee.image.height:null,Se=N[p.type];p.precision!==null&&(A=c.getMaxPrecision(p.precision),A!==p.precision&&console.warn("THREE.WebGLProgram.getParameters:",p.precision,"not supported, using",A,"instead."));let Ae=J.morphAttributes.position||J.morphAttributes.normal||J.morphAttributes.color,we=Ae!==void 0?Ae.length:0,He=0;J.morphAttributes.position!==void 0&&(He=1),J.morphAttributes.normal!==void 0&&(He=2),J.morphAttributes.color!==void 0&&(He=3);let je,k,j,_e;if(Se){let ke=gt[Se];je=ke.vertexShader,k=ke.fragmentShader}else je=p.vertexShader,k=p.fragmentShader,C.update(p),j=C.getVertexShaderID(p),_e=C.getFragmentShaderID(p);let oe=e.getRenderTarget(),ve=e.state.buffers.depth.getReversed(),Fe=V.isInstancedMesh===!0,Re=V.isBatchedMesh===!0,Ze=!!p.map,Qe=!!p.matcap,Be=!!ee,m=!!p.aoMap,ot=!!p.lightMap,Ge=!!p.bumpMap,Xe=!!p.normalMap,pe=!!p.displacementMap,ye=!!p.emissiveMap,Ee=!!p.metalnessMap,Ue=!!p.roughnessMap,nt=p.anisotropy>0,u=p.clearcoat>0,a=p.dispersion>0,b=p.iridescence>0,B=p.sheen>0,X=p.transmission>0,O=nt&&!!p.anisotropyMap,he=u&&!!p.clearcoatMap,ie=u&&!!p.clearcoatNormalMap,ue=u&&!!p.clearcoatRoughnessMap,me=b&&!!p.iridescenceMap,q=b&&!!p.iridescenceThicknessMap,se=B&&!!p.sheenColorMap,xe=B&&!!p.sheenRoughnessMap,Te=!!p.specularMap,te=!!p.specularColorMap,Pe=!!p.specularIntensityMap,v=X&&!!p.transmissionMap,re=X&&!!p.thicknessMap,$=!!p.gradientMap,le=!!p.alphaMap,Z=p.alphaTest>0,z=!!p.alphaHash,fe=!!p.extensions,Le=At;p.toneMapped&&(oe===null||oe.isXRRenderTarget===!0)&&(Le=e.toneMapping);let Ke={shaderID:Se,shaderType:p.type,shaderName:p.name,vertexShader:je,fragmentShader:k,defines:p.defines,customVertexShaderID:j,customFragmentShaderID:_e,isRawShaderMaterial:p.isRawShaderMaterial===!0,glslVersion:p.glslVersion,precision:A,batching:Re,batchingColor:Re&&V._colorsTexture!==null,instancing:Fe,instancingColor:Fe&&V.instanceColor!==null,instancingMorph:Fe&&V.morphTexture!==null,supportsVertexTextures:g,outputColorSpace:oe===null?e.outputColorSpace:oe.isXRRenderTarget===!0?oe.texture.colorSpace:vn,alphaToCoverage:!!p.alphaToCoverage,map:Ze,matcap:Qe,envMap:Be,envMapMode:Be&&ee.mapping,envMapCubeUVHeight:F,aoMap:m,lightMap:ot,bumpMap:Ge,normalMap:Xe,displacementMap:g&&pe,emissiveMap:ye,normalMapObjectSpace:Xe&&p.normalMapType===oa,normalMapTangentSpace:Xe&&p.normalMapType===aa,metalnessMap:Ee,roughnessMap:Ue,anisotropy:nt,anisotropyMap:O,clearcoat:u,clearcoatMap:he,clearcoatNormalMap:ie,clearcoatRoughnessMap:ue,dispersion:a,iridescence:b,iridescenceMap:me,iridescenceThicknessMap:q,sheen:B,sheenColorMap:se,sheenRoughnessMap:xe,specularMap:Te,specularColorMap:te,specularIntensityMap:Pe,transmission:X,transmissionMap:v,thicknessMap:re,gradientMap:$,opaque:p.transparent===!1&&p.blending===fn&&p.alphaToCoverage===!1,alphaMap:le,alphaTest:Z,alphaHash:z,combine:p.combine,mapUv:Ze&&L(p.map.channel),aoMapUv:m&&L(p.aoMap.channel),lightMapUv:ot&&L(p.lightMap.channel),bumpMapUv:Ge&&L(p.bumpMap.channel),normalMapUv:Xe&&L(p.normalMap.channel),displacementMapUv:pe&&L(p.displacementMap.channel),emissiveMapUv:ye&&L(p.emissiveMap.channel),metalnessMapUv:Ee&&L(p.metalnessMap.channel),roughnessMapUv:Ue&&L(p.roughnessMap.channel),anisotropyMapUv:O&&L(p.anisotropyMap.channel),clearcoatMapUv:he&&L(p.clearcoatMap.channel),clearcoatNormalMapUv:ie&&L(p.clearcoatNormalMap.channel),clearcoatRoughnessMapUv:ue&&L(p.clearcoatRoughnessMap.channel),iridescenceMapUv:me&&L(p.iridescenceMap.channel),iridescenceThicknessMapUv:q&&L(p.iridescenceThicknessMap.channel),sheenColorMapUv:se&&L(p.sheenColorMap.channel),sheenRoughnessMapUv:xe&&L(p.sheenRoughnessMap.channel),specularMapUv:Te&&L(p.specularMap.channel),specularColorMapUv:te&&L(p.specularColorMap.channel),specularIntensityMapUv:Pe&&L(p.specularIntensityMap.channel),transmissionMapUv:v&&L(p.transmissionMap.channel),thicknessMapUv:re&&L(p.thicknessMap.channel),alphaMapUv:le&&L(p.alphaMap.channel),vertexTangents:!!J.attributes.tangent&&(Xe||nt),vertexColors:p.vertexColors,vertexAlphas:p.vertexColors===!0&&!!J.attributes.color&&J.attributes.color.itemSize===4,pointsUvs:V.isPoints===!0&&!!J.attributes.uv&&(Ze||le),fog:!!K,useFog:p.fog===!0,fogExp2:!!K&&K.isFogExp2,flatShading:p.flatShading===!0,sizeAttenuation:p.sizeAttenuation===!0,logarithmicDepthBuffer:T,reverseDepthBuffer:ve,skinning:V.isSkinnedMesh===!0,morphTargets:J.morphAttributes.position!==void 0,morphNormals:J.morphAttributes.normal!==void 0,morphColors:J.morphAttributes.color!==void 0,morphTargetsCount:we,morphTextureStride:He,numDirLights:f.directional.length,numPointLights:f.point.length,numSpotLights:f.spot.length,numSpotLightMaps:f.spotLightMap.length,numRectAreaLights:f.rectArea.length,numHemiLights:f.hemi.length,numDirLightShadows:f.directionalShadowMap.length,numPointLightShadows:f.pointShadowMap.length,numSpotLightShadows:f.spotShadowMap.length,numSpotLightShadowsWithMaps:f.numSpotLightShadowsWithMaps,numLightProbes:f.numLightProbes,numClippingPlanes:h.numPlanes,numClipIntersection:h.numIntersection,dithering:p.dithering,shadowMapEnabled:e.shadowMap.enabled&&R.length>0,shadowMapType:e.shadowMap.type,toneMapping:Le,decodeVideoTexture:Ze&&p.map.isVideoTexture===!0&&tt.getTransfer(p.map.colorSpace)===Ye,decodeVideoTextureEmissive:ye&&p.emissiveMap.isVideoTexture===!0&&tt.getTransfer(p.emissiveMap.colorSpace)===Ye,premultipliedAlpha:p.premultipliedAlpha,doubleSided:p.side===Mt,flipSided:p.side===mt,useDepthPacking:p.depthPacking>=0,depthPacking:p.depthPacking||0,index0AttributeName:p.index0AttributeName,extensionClipCullDistance:fe&&p.extensions.clipCullDistance===!0&&i.has("WEBGL_clip_cull_distance"),extensionMultiDraw:(fe&&p.extensions.multiDraw===!0||Re)&&i.has("WEBGL_multi_draw"),rendererExtensionParallelShaderCompile:i.has("KHR_parallel_shader_compile"),customProgramCacheKey:p.customProgramCacheKey()};return Ke.vertexUv1s=M.has(1),Ke.vertexUv2s=M.has(2),Ke.vertexUv3s=M.has(3),M.clear(),Ke}function r(p){let f=[];if(p.shaderID?f.push(p.shaderID):(f.push(p.customVertexShaderID),f.push(p.customFragmentShaderID)),p.defines!==void 0)for(let R in p.defines)f.push(R),f.push(p.defines[R]);return p.isRawShaderMaterial===!1&&(U(f,p),x(f,p),f.push(e.outputColorSpace)),f.push(p.customProgramCacheKey),f.join()}function U(p,f){p.push(f.precision),p.push(f.outputColorSpace),p.push(f.envMapMode),p.push(f.envMapCubeUVHeight),p.push(f.mapUv),p.push(f.alphaMapUv),p.push(f.lightMapUv),p.push(f.aoMapUv),p.push(f.bumpMapUv),p.push(f.normalMapUv),p.push(f.displacementMapUv),p.push(f.emissiveMapUv),p.push(f.metalnessMapUv),p.push(f.roughnessMapUv),p.push(f.anisotropyMapUv),p.push(f.clearcoatMapUv),p.push(f.clearcoatNormalMapUv),p.push(f.clearcoatRoughnessMapUv),p.push(f.iridescenceMapUv),p.push(f.iridescenceThicknessMapUv),p.push(f.sheenColorMapUv),p.push(f.sheenRoughnessMapUv),p.push(f.specularMapUv),p.push(f.specularColorMapUv),p.push(f.specularIntensityMapUv),p.push(f.transmissionMapUv),p.push(f.thicknessMapUv),p.push(f.combine),p.push(f.fogExp2),p.push(f.sizeAttenuation),p.push(f.morphTargetsCount),p.push(f.morphAttributeCount),p.push(f.numDirLights),p.push(f.numPointLights),p.push(f.numSpotLights),p.push(f.numSpotLightMaps),p.push(f.numHemiLights),p.push(f.numRectAreaLights),p.push(f.numDirLightShadows),p.push(f.numPointLightShadows),p.push(f.numSpotLightShadows),p.push(f.numSpotLightShadowsWithMaps),p.push(f.numLightProbes),p.push(f.shadowMapType),p.push(f.toneMapping),p.push(f.numClippingPlanes),p.push(f.numClipIntersection),p.push(f.depthPacking)}function x(p,f){d.disableAll(),f.supportsVertexTextures&&d.enable(0),f.instancing&&d.enable(1),f.instancingColor&&d.enable(2),f.instancingMorph&&d.enable(3),f.matcap&&d.enable(4),f.envMap&&d.enable(5),f.normalMapObjectSpace&&d.enable(6),f.normalMapTangentSpace&&d.enable(7),f.clearcoat&&d.enable(8),f.iridescence&&d.enable(9),f.alphaTest&&d.enable(10),f.vertexColors&&d.enable(11),f.vertexAlphas&&d.enable(12),f.vertexUv1s&&d.enable(13),f.vertexUv2s&&d.enable(14),f.vertexUv3s&&d.enable(15),f.vertexTangents&&d.enable(16),f.anisotropy&&d.enable(17),f.alphaHash&&d.enable(18),f.batching&&d.enable(19),f.dispersion&&d.enable(20),f.batchingColor&&d.enable(21),p.push(d.mask),d.disableAll(),f.fog&&d.enable(0),f.useFog&&d.enable(1),f.flatShading&&d.enable(2),f.logarithmicDepthBuffer&&d.enable(3),f.reverseDepthBuffer&&d.enable(4),f.skinning&&d.enable(5),f.morphTargets&&d.enable(6),f.morphNormals&&d.enable(7),f.morphColors&&d.enable(8),f.premultipliedAlpha&&d.enable(9),f.shadowMapEnabled&&d.enable(10),f.doubleSided&&d.enable(11),f.flipSided&&d.enable(12),f.useDepthPacking&&d.enable(13),f.dithering&&d.enable(14),f.transmission&&d.enable(15),f.sheen&&d.enable(16),f.opaque&&d.enable(17),f.pointsUvs&&d.enable(18),f.decodeVideoTexture&&d.enable(19),f.decodeVideoTextureEmissive&&d.enable(20),f.alphaToCoverage&&d.enable(21),p.push(d.mask)}function _(p){let f=N[p.type],R;if(f){let Y=gt[f];R=ra.clone(Y.uniforms)}else R=p.uniforms;return R}function H(p,f){let R;for(let Y=0,V=D.length;Y<V;Y++){let K=D[Y];if(K.cacheKey===f){R=K,++R.usedTimes;break}}return R===void 0&&(R=new mf(e,f,p,o),D.push(R)),R}function P(p){if(--p.usedTimes===0){let f=D.indexOf(p);D[f]=D[D.length-1],D.pop(),p.destroy()}}function y(p){C.remove(p)}function G(){C.dispose()}return{getParameters:l,getProgramCacheKey:r,getUniforms:_,acquireProgram:H,releaseProgram:P,releaseShaderCache:y,programs:D,dispose:G}}function gf(){let e=new WeakMap;function n(h){return e.has(h)}function t(h){let d=e.get(h);return d===void 0&&(d={},e.set(h,d)),d}function i(h){e.delete(h)}function c(h,d,C){e.get(h)[d]=C}function o(){e=new WeakMap}return{has:n,get:t,remove:i,update:c,dispose:o}}function Sf(e,n){return e.groupOrder!==n.groupOrder?e.groupOrder-n.groupOrder:e.renderOrder!==n.renderOrder?e.renderOrder-n.renderOrder:e.material.id!==n.material.id?e.material.id-n.material.id:e.z!==n.z?e.z-n.z:e.id-n.id}function ar(e,n){return e.groupOrder!==n.groupOrder?e.groupOrder-n.groupOrder:e.renderOrder!==n.renderOrder?e.renderOrder-n.renderOrder:e.z!==n.z?n.z-e.z:e.id-n.id}function or(){let e=[],n=0,t=[],i=[],c=[];function o(){n=0,t.length=0,i.length=0,c.length=0}function h(T,g,A,N,L,l){let r=e[n];return r===void 0?(r={id:T.id,object:T,geometry:g,material:A,groupOrder:N,renderOrder:T.renderOrder,z:L,group:l},e[n]=r):(r.id=T.id,r.object=T,r.geometry=g,r.material=A,r.groupOrder=N,r.renderOrder=T.renderOrder,r.z=L,r.group=l),n++,r}function d(T,g,A,N,L,l){let r=h(T,g,A,N,L,l);A.transmission>0?i.push(r):A.transparent===!0?c.push(r):t.push(r)}function C(T,g,A,N,L,l){let r=h(T,g,A,N,L,l);A.transmission>0?i.unshift(r):A.transparent===!0?c.unshift(r):t.unshift(r)}function M(T,g){t.length>1&&t.sort(T||Sf),i.length>1&&i.sort(g||ar),c.length>1&&c.sort(g||ar)}function D(){for(let T=n,g=e.length;T<g;T++){let A=e[T];if(A.id===null)break;A.id=null,A.object=null,A.geometry=null,A.material=null,A.group=null}}return{opaque:t,transmissive:i,transparent:c,init:o,push:d,unshift:C,finish:D,sort:M}}function Ef(){let e=new WeakMap;function n(i,c){let o=e.get(i),h;return o===void 0?(h=new or,e.set(i,[h])):c>=o.length?(h=new or,o.push(h)):h=o[c],h}function t(){e=new WeakMap}return{get:n,dispose:t}}function Mf(){let e={};return{get:function(n){if(e[n.id]!==void 0)return e[n.id];let t;switch(n.type){case"DirectionalLight":t={direction:new We,color:new $e};break;case"SpotLight":t={position:new We,direction:new We,color:new $e,distance:0,coneCos:0,penumbraCos:0,decay:0};break;case"PointLight":t={position:new We,color:new $e,distance:0,decay:0};break;case"HemisphereLight":t={direction:new We,skyColor:new $e,groundColor:new $e};break;case"RectAreaLight":t={color:new $e,position:new We,halfWidth:new We,halfHeight:new We};break}return e[n.id]=t,t}}}function Tf(){let e={};return{get:function(n){if(e[n.id]!==void 0)return e[n.id];let t;switch(n.type){case"DirectionalLight":t={shadowIntensity:1,shadowBias:0,shadowNormalBias:0,shadowRadius:1,shadowMapSize:new dt};break;case"SpotLight":t={shadowIntensity:1,shadowBias:0,shadowNormalBias:0,shadowRadius:1,shadowMapSize:new dt};break;case"PointLight":t={shadowIntensity:1,shadowBias:0,shadowNormalBias:0,shadowRadius:1,shadowMapSize:new dt,shadowCameraNear:1,shadowCameraFar:1e3};break}return e[n.id]=t,t}}}var xf=0;function Af(e,n){return(n.castShadow?2:0)-(e.castShadow?2:0)+(n.map?1:0)-(e.map?1:0)}function Rf(e){let n=new Mf,t=Tf(),i={version:0,hash:{directionalLength:-1,pointLength:-1,spotLength:-1,rectAreaLength:-1,hemiLength:-1,numDirectionalShadows:-1,numPointShadows:-1,numSpotShadows:-1,numSpotMaps:-1,numLightProbes:-1},ambient:[0,0,0],probe:[],directional:[],directionalShadow:[],directionalShadowMap:[],directionalShadowMatrix:[],spot:[],spotLightMap:[],spotShadow:[],spotShadowMap:[],spotLightMatrix:[],rectArea:[],rectAreaLTC1:null,rectAreaLTC2:null,point:[],pointShadow:[],pointShadowMap:[],pointShadowMatrix:[],hemi:[],numSpotLightShadowsWithMaps:0,numLightProbes:0};for(let M=0;M<9;M++)i.probe.push(new We);let c=new We,o=new Vt,h=new Vt;function d(M){let D=0,T=0,g=0;for(let p=0;p<9;p++)i.probe[p].set(0,0,0);let A=0,N=0,L=0,l=0,r=0,U=0,x=0,_=0,H=0,P=0,y=0;M.sort(Af);for(let p=0,f=M.length;p<f;p++){let R=M[p],Y=R.color,V=R.intensity,K=R.distance,J=R.shadow&&R.shadow.map?R.shadow.map.texture:null;if(R.isAmbientLight)D+=Y.r*V,T+=Y.g*V,g+=Y.b*V;else if(R.isLightProbe){for(let W=0;W<9;W++)i.probe[W].addScaledVector(R.sh.coefficients[W],V);y++}else if(R.isDirectionalLight){let W=n.get(R);if(W.color.copy(R.color).multiplyScalar(R.intensity),R.castShadow){let ee=R.shadow,F=t.get(R);F.shadowIntensity=ee.intensity,F.shadowBias=ee.bias,F.shadowNormalBias=ee.normalBias,F.shadowRadius=ee.radius,F.shadowMapSize=ee.mapSize,i.directionalShadow[A]=F,i.directionalShadowMap[A]=J,i.directionalShadowMatrix[A]=R.shadow.matrix,U++}i.directional[A]=W,A++}else if(R.isSpotLight){let W=n.get(R);W.position.setFromMatrixPosition(R.matrixWorld),W.color.copy(Y).multiplyScalar(V),W.distance=K,W.coneCos=Math.cos(R.angle),W.penumbraCos=Math.cos(R.angle*(1-R.penumbra)),W.decay=R.decay,i.spot[L]=W;let ee=R.shadow;if(R.map&&(i.spotLightMap[H]=R.map,H++,ee.updateMatrices(R),R.castShadow&&P++),i.spotLightMatrix[L]=ee.matrix,R.castShadow){let F=t.get(R);F.shadowIntensity=ee.intensity,F.shadowBias=ee.bias,F.shadowNormalBias=ee.normalBias,F.shadowRadius=ee.radius,F.shadowMapSize=ee.mapSize,i.spotShadow[L]=F,i.spotShadowMap[L]=J,_++}L++}else if(R.isRectAreaLight){let W=n.get(R);W.color.copy(Y).multiplyScalar(V),W.halfWidth.set(R.width*.5,0,0),W.halfHeight.set(0,R.height*.5,0),i.rectArea[l]=W,l++}else if(R.isPointLight){let W=n.get(R);if(W.color.copy(R.color).multiplyScalar(R.intensity),W.distance=R.distance,W.decay=R.decay,R.castShadow){let ee=R.shadow,F=t.get(R);F.shadowIntensity=ee.intensity,F.shadowBias=ee.bias,F.shadowNormalBias=ee.normalBias,F.shadowRadius=ee.radius,F.shadowMapSize=ee.mapSize,F.shadowCameraNear=ee.camera.near,F.shadowCameraFar=ee.camera.far,i.pointShadow[N]=F,i.pointShadowMap[N]=J,i.pointShadowMatrix[N]=R.shadow.matrix,x++}i.point[N]=W,N++}else if(R.isHemisphereLight){let W=n.get(R);W.skyColor.copy(R.color).multiplyScalar(V),W.groundColor.copy(R.groundColor).multiplyScalar(V),i.hemi[r]=W,r++}}l>0&&(e.has("OES_texture_float_linear")===!0?(i.rectAreaLTC1=ne.LTC_FLOAT_1,i.rectAreaLTC2=ne.LTC_FLOAT_2):(i.rectAreaLTC1=ne.LTC_HALF_1,i.rectAreaLTC2=ne.LTC_HALF_2)),i.ambient[0]=D,i.ambient[1]=T,i.ambient[2]=g;let G=i.hash;(G.directionalLength!==A||G.pointLength!==N||G.spotLength!==L||G.rectAreaLength!==l||G.hemiLength!==r||G.numDirectionalShadows!==U||G.numPointShadows!==x||G.numSpotShadows!==_||G.numSpotMaps!==H||G.numLightProbes!==y)&&(i.directional.length=A,i.spot.length=L,i.rectArea.length=l,i.point.length=N,i.hemi.length=r,i.directionalShadow.length=U,i.directionalShadowMap.length=U,i.pointShadow.length=x,i.pointShadowMap.length=x,i.spotShadow.length=_,i.spotShadowMap.length=_,i.directionalShadowMatrix.length=U,i.pointShadowMatrix.length=x,i.spotLightMatrix.length=_+H-P,i.spotLightMap.length=H,i.numSpotLightShadowsWithMaps=P,i.numLightProbes=y,G.directionalLength=A,G.pointLength=N,G.spotLength=L,G.rectAreaLength=l,G.hemiLength=r,G.numDirectionalShadows=U,G.numPointShadows=x,G.numSpotShadows=_,G.numSpotMaps=H,G.numLightProbes=y,i.version=xf++)}function C(M,D){let T=0,g=0,A=0,N=0,L=0,l=D.matrixWorldInverse;for(let r=0,U=M.length;r<U;r++){let x=M[r];if(x.isDirectionalLight){let _=i.directional[T];_.direction.setFromMatrixPosition(x.matrixWorld),c.setFromMatrixPosition(x.target.matrixWorld),_.direction.sub(c),_.direction.transformDirection(l),T++}else if(x.isSpotLight){let _=i.spot[A];_.position.setFromMatrixPosition(x.matrixWorld),_.position.applyMatrix4(l),_.direction.setFromMatrixPosition(x.matrixWorld),c.setFromMatrixPosition(x.target.matrixWorld),_.direction.sub(c),_.direction.transformDirection(l),A++}else if(x.isRectAreaLight){let _=i.rectArea[N];_.position.setFromMatrixPosition(x.matrixWorld),_.position.applyMatrix4(l),h.identity(),o.copy(x.matrixWorld),o.premultiply(l),h.extractRotation(o),_.halfWidth.set(x.width*.5,0,0),_.halfHeight.set(0,x.height*.5,0),_.halfWidth.applyMatrix4(h),_.halfHeight.applyMatrix4(h),N++}else if(x.isPointLight){let _=i.point[g];_.position.setFromMatrixPosition(x.matrixWorld),_.position.applyMatrix4(l),g++}else if(x.isHemisphereLight){let _=i.hemi[L];_.direction.setFromMatrixPosition(x.matrixWorld),_.direction.transformDirection(l),L++}}}return{setup:d,setupView:C,state:i}}function sr(e){let n=new Rf(e),t=[],i=[];function c(D){M.camera=D,t.length=0,i.length=0}function o(D){t.push(D)}function h(D){i.push(D)}function d(){n.setup(t)}function C(D){n.setupView(t,D)}let M={lightsArray:t,shadowsArray:i,camera:null,lights:n,transmissionRenderTarget:{}};return{init:c,state:M,setupLights:d,setupLightsView:C,pushLight:o,pushShadow:h}}function Cf(e){let n=new WeakMap;function t(c,o=0){let h=n.get(c),d;return h===void 0?(d=new sr(e),n.set(c,[d])):o>=h.length?(d=new sr(e),h.push(d)):d=h[o],d}function i(){n=new WeakMap}return{get:t,dispose:i}}var bf=`void main() {
	gl_Position = vec4( position, 1.0 );
}`,Pf=`uniform sampler2D shadow_pass;
uniform vec2 resolution;
uniform float radius;
#include <packing>
void main() {
	const float samples = float( VSM_SAMPLES );
	float mean = 0.0;
	float squared_mean = 0.0;
	float uvStride = samples <= 1.0 ? 0.0 : 2.0 / ( samples - 1.0 );
	float uvStart = samples <= 1.0 ? 0.0 : - 1.0;
	for ( float i = 0.0; i < samples; i ++ ) {
		float uvOffset = uvStart + i * uvStride;
		#ifdef HORIZONTAL_PASS
			vec2 distribution = unpackRGBATo2Half( texture2D( shadow_pass, ( gl_FragCoord.xy + vec2( uvOffset, 0.0 ) * radius ) / resolution ) );
			mean += distribution.x;
			squared_mean += distribution.y * distribution.y + distribution.x * distribution.x;
		#else
			float depth = unpackRGBAToDepth( texture2D( shadow_pass, ( gl_FragCoord.xy + vec2( 0.0, uvOffset ) * radius ) / resolution ) );
			mean += depth;
			squared_mean += depth * depth;
		#endif
	}
	mean = mean / samples;
	squared_mean = squared_mean / samples;
	float std_dev = sqrt( squared_mean - mean * mean );
	gl_FragColor = pack2HalfToRGBA( vec2( mean, std_dev ) );
}`;function Lf(e,n,t){let i=new Mr,c=new dt,o=new dt,h=new ft,d=new ca({depthPacking:la}),C=new fa,M={},D=t.maxTextureSize,T={[Zt]:mt,[mt]:Zt,[Mt]:Mt},g=new It({defines:{VSM_SAMPLES:8},uniforms:{shadow_pass:{value:null},resolution:{value:new dt},radius:{value:4}},vertexShader:bf,fragmentShader:Pf}),A=g.clone();A.defines.HORIZONTAL_PASS=1;let N=new hr;N.setAttribute("position",new cn(new Float32Array([-1,-1,.5,3,-1,.5,-1,3,.5]),3));let L=new xt(N,g),l=this;this.enabled=!1,this.autoUpdate=!0,this.needsUpdate=!1,this.type=Sr;let r=this.type;this.render=function(P,y,G){if(l.enabled===!1||l.autoUpdate===!1&&l.needsUpdate===!1||P.length===0)return;let p=e.getRenderTarget(),f=e.getActiveCubeFace(),R=e.getActiveMipmapLevel(),Y=e.state;Y.setBlending(wt),Y.buffers.color.setClear(1,1,1,1),Y.buffers.depth.setTest(!0),Y.setScissorTest(!1);let V=r!==Et&&this.type===Et,K=r===Et&&this.type!==Et;for(let J=0,W=P.length;J<W;J++){let ee=P[J],F=ee.shadow;if(F===void 0){console.warn("THREE.WebGLShadowMap:",ee,"has no shadow.");continue}if(F.autoUpdate===!1&&F.needsUpdate===!1)continue;c.copy(F.mapSize);let Se=F.getFrameExtents();if(c.multiply(Se),o.copy(F.mapSize),(c.x>D||c.y>D)&&(c.x>D&&(o.x=Math.floor(D/Se.x),c.x=o.x*Se.x,F.mapSize.x=o.x),c.y>D&&(o.y=Math.floor(D/Se.y),c.y=o.y*Se.y,F.mapSize.y=o.y)),F.map===null||V===!0||K===!0){let we=this.type!==Et?{minFilter:$t,magFilter:$t}:{};F.map!==null&&F.map.dispose(),F.map=new zt(c.x,c.y,we),F.map.texture.name=ee.name+".shadowMap",F.camera.updateProjectionMatrix()}e.setRenderTarget(F.map),e.clear();let Ae=F.getViewportCount();for(let we=0;we<Ae;we++){let He=F.getViewport(we);h.set(o.x*He.x,o.y*He.y,o.x*He.z,o.y*He.w),Y.viewport(h),F.updateMatrices(ee,we),i=F.getFrustum(),_(y,G,F.camera,ee,this.type)}F.isPointLightShadow!==!0&&this.type===Et&&U(F,G),F.needsUpdate=!1}r=this.type,l.needsUpdate=!1,e.setRenderTarget(p,f,R)};function U(P,y){let G=n.update(L);g.defines.VSM_SAMPLES!==P.blurSamples&&(g.defines.VSM_SAMPLES=P.blurSamples,A.defines.VSM_SAMPLES=P.blurSamples,g.needsUpdate=!0,A.needsUpdate=!0),P.mapPass===null&&(P.mapPass=new zt(c.x,c.y)),g.uniforms.shadow_pass.value=P.map.texture,g.uniforms.resolution.value=P.mapSize,g.uniforms.radius.value=P.radius,e.setRenderTarget(P.mapPass),e.clear(),e.renderBufferDirect(y,null,G,g,L,null),A.uniforms.shadow_pass.value=P.mapPass.texture,A.uniforms.resolution.value=P.mapSize,A.uniforms.radius.value=P.radius,e.setRenderTarget(P.map),e.clear(),e.renderBufferDirect(y,null,G,A,L,null)}function x(P,y,G,p){let f=null,R=G.isPointLight===!0?P.customDistanceMaterial:P.customDepthMaterial;if(R!==void 0)f=R;else if(f=G.isPointLight===!0?C:d,e.localClippingEnabled&&y.clipShadows===!0&&Array.isArray(y.clippingPlanes)&&y.clippingPlanes.length!==0||y.displacementMap&&y.displacementScale!==0||y.alphaMap&&y.alphaTest>0||y.map&&y.alphaTest>0||y.alphaToCoverage===!0){let Y=f.uuid,V=y.uuid,K=M[Y];K===void 0&&(K={},M[Y]=K);let J=K[V];J===void 0&&(J=f.clone(),K[V]=J,y.addEventListener("dispose",H)),f=J}if(f.visible=y.visible,f.wireframe=y.wireframe,p===Et?f.side=y.shadowSide!==null?y.shadowSide:y.side:f.side=y.shadowSide!==null?y.shadowSide:T[y.side],f.alphaMap=y.alphaMap,f.alphaTest=y.alphaToCoverage===!0?.5:y.alphaTest,f.map=y.map,f.clipShadows=y.clipShadows,f.clippingPlanes=y.clippingPlanes,f.clipIntersection=y.clipIntersection,f.displacementMap=y.displacementMap,f.displacementScale=y.displacementScale,f.displacementBias=y.displacementBias,f.wireframeLinewidth=y.wireframeLinewidth,f.linewidth=y.linewidth,G.isPointLight===!0&&f.isMeshDistanceMaterial===!0){let Y=e.properties.get(f);Y.light=G}return f}function _(P,y,G,p,f){if(P.visible===!1)return;if(P.layers.test(y.layers)&&(P.isMesh||P.isLine||P.isPoints)&&(P.castShadow||P.receiveShadow&&f===Et)&&(!P.frustumCulled||i.intersectsObject(P))){P.modelViewMatrix.multiplyMatrices(G.matrixWorldInverse,P.matrixWorld);let V=n.update(P),K=P.material;if(Array.isArray(K)){let J=V.groups;for(let W=0,ee=J.length;W<ee;W++){let F=J[W],Se=K[F.materialIndex];if(Se&&Se.visible){let Ae=x(P,Se,p,f);P.onBeforeShadow(e,P,y,G,V,Ae,F),e.renderBufferDirect(G,null,V,Ae,P,F),P.onAfterShadow(e,P,y,G,V,Ae,F)}}}else if(K.visible){let J=x(P,K,p,f);P.onBeforeShadow(e,P,y,G,V,J,null),e.renderBufferDirect(G,null,V,J,P,null),P.onAfterShadow(e,P,y,G,V,J,null)}}let Y=P.children;for(let V=0,K=Y.length;V<K;V++)_(Y[V],y,G,p,f)}function H(P){P.target.removeEventListener("dispose",H);for(let G in M){let p=M[G],f=P.target.uuid;f in p&&(p[f].dispose(),delete p[f])}}}var Uf={[kn]:Vn,[Hn]:Fn,[Gn]:On,[dn]:Bn,[Vn]:kn,[Fn]:Hn,[On]:Gn,[Bn]:dn};function Df(e,n){function t(){let v=!1,re=new ft,$=null,le=new ft(0,0,0,0);return{setMask:function(Z){$!==Z&&!v&&(e.colorMask(Z,Z,Z,Z),$=Z)},setLocked:function(Z){v=Z},setClear:function(Z,z,fe,Le,Ke){Ke===!0&&(Z*=Le,z*=Le,fe*=Le),re.set(Z,z,fe,Le),le.equals(re)===!1&&(e.clearColor(Z,z,fe,Le),le.copy(re))},reset:function(){v=!1,$=null,le.set(-1,0,0,0)}}}function i(){let v=!1,re=!1,$=null,le=null,Z=null;return{setReversed:function(z){if(re!==z){let fe=n.get("EXT_clip_control");z?fe.clipControlEXT(fe.LOWER_LEFT_EXT,fe.ZERO_TO_ONE_EXT):fe.clipControlEXT(fe.LOWER_LEFT_EXT,fe.NEGATIVE_ONE_TO_ONE_EXT),re=z;let Le=Z;Z=null,this.setClear(Le)}},getReversed:function(){return re},setTest:function(z){z?oe(e.DEPTH_TEST):ve(e.DEPTH_TEST)},setMask:function(z){$!==z&&!v&&(e.depthMask(z),$=z)},setFunc:function(z){if(re&&(z=Uf[z]),le!==z){switch(z){case kn:e.depthFunc(e.NEVER);break;case Vn:e.depthFunc(e.ALWAYS);break;case Hn:e.depthFunc(e.LESS);break;case dn:e.depthFunc(e.LEQUAL);break;case Gn:e.depthFunc(e.EQUAL);break;case Bn:e.depthFunc(e.GEQUAL);break;case Fn:e.depthFunc(e.GREATER);break;case On:e.depthFunc(e.NOTEQUAL);break;default:e.depthFunc(e.LEQUAL)}le=z}},setLocked:function(z){v=z},setClear:function(z){Z!==z&&(re&&(z=1-z),e.clearDepth(z),Z=z)},reset:function(){v=!1,$=null,le=null,Z=null,re=!1}}}function c(){let v=!1,re=null,$=null,le=null,Z=null,z=null,fe=null,Le=null,Ke=null;return{setTest:function(ke){v||(ke?oe(e.STENCIL_TEST):ve(e.STENCIL_TEST))},setMask:function(ke){re!==ke&&!v&&(e.stencilMask(ke),re=ke)},setFunc:function(ke,_t,St){($!==ke||le!==_t||Z!==St)&&(e.stencilFunc(ke,_t,St),$=ke,le=_t,Z=St)},setOp:function(ke,_t,St){(z!==ke||fe!==_t||Le!==St)&&(e.stencilOp(ke,_t,St),z=ke,fe=_t,Le=St)},setLocked:function(ke){v=ke},setClear:function(ke){Ke!==ke&&(e.clearStencil(ke),Ke=ke)},reset:function(){v=!1,re=null,$=null,le=null,Z=null,z=null,fe=null,Le=null,Ke=null}}}let o=new t,h=new i,d=new c,C=new WeakMap,M=new WeakMap,D={},T={},g=new WeakMap,A=[],N=null,L=!1,l=null,r=null,U=null,x=null,_=null,H=null,P=null,y=new $e(0,0,0),G=0,p=!1,f=null,R=null,Y=null,V=null,K=null,J=e.getParameter(e.MAX_COMBINED_TEXTURE_IMAGE_UNITS),W=!1,ee=0,F=e.getParameter(e.VERSION);F.indexOf("WebGL")!==-1?(ee=parseFloat(/^WebGL (\d)/.exec(F)[1]),W=ee>=1):F.indexOf("OpenGL ES")!==-1&&(ee=parseFloat(/^OpenGL ES (\d)/.exec(F)[1]),W=ee>=2);let Se=null,Ae={},we=e.getParameter(e.SCISSOR_BOX),He=e.getParameter(e.VIEWPORT),je=new ft().fromArray(we),k=new ft().fromArray(He);function j(v,re,$,le){let Z=new Uint8Array(4),z=e.createTexture();e.bindTexture(v,z),e.texParameteri(v,e.TEXTURE_MIN_FILTER,e.NEAREST),e.texParameteri(v,e.TEXTURE_MAG_FILTER,e.NEAREST);for(let fe=0;fe<$;fe++)v===e.TEXTURE_3D||v===e.TEXTURE_2D_ARRAY?e.texImage3D(re,0,e.RGBA,1,1,le,0,e.RGBA,e.UNSIGNED_BYTE,Z):e.texImage2D(re+fe,0,e.RGBA,1,1,0,e.RGBA,e.UNSIGNED_BYTE,Z);return z}let _e={};_e[e.TEXTURE_2D]=j(e.TEXTURE_2D,e.TEXTURE_2D,1),_e[e.TEXTURE_CUBE_MAP]=j(e.TEXTURE_CUBE_MAP,e.TEXTURE_CUBE_MAP_POSITIVE_X,6),_e[e.TEXTURE_2D_ARRAY]=j(e.TEXTURE_2D_ARRAY,e.TEXTURE_2D_ARRAY,1,1),_e[e.TEXTURE_3D]=j(e.TEXTURE_3D,e.TEXTURE_3D,1,1),o.setClear(0,0,0,1),h.setClear(1),d.setClear(0),oe(e.DEPTH_TEST),h.setFunc(dn),Ge(!1),Xe(ci),oe(e.CULL_FACE),m(wt);function oe(v){D[v]!==!0&&(e.enable(v),D[v]=!0)}function ve(v){D[v]!==!1&&(e.disable(v),D[v]=!1)}function Fe(v,re){return T[v]!==re?(e.bindFramebuffer(v,re),T[v]=re,v===e.DRAW_FRAMEBUFFER&&(T[e.FRAMEBUFFER]=re),v===e.FRAMEBUFFER&&(T[e.DRAW_FRAMEBUFFER]=re),!0):!1}function Re(v,re){let $=A,le=!1;if(v){$=g.get(re),$===void 0&&($=[],g.set(re,$));let Z=v.textures;if($.length!==Z.length||$[0]!==e.COLOR_ATTACHMENT0){for(let z=0,fe=Z.length;z<fe;z++)$[z]=e.COLOR_ATTACHMENT0+z;$.length=Z.length,le=!0}}else $[0]!==e.BACK&&($[0]=e.BACK,le=!0);le&&e.drawBuffers($)}function Ze(v){return N!==v?(e.useProgram(v),N=v,!0):!1}let Qe={[Kt]:e.FUNC_ADD,[ua]:e.FUNC_SUBTRACT,[da]:e.FUNC_REVERSE_SUBTRACT};Qe[Da]=e.MIN,Qe[wa]=e.MAX;let Be={[ba]:e.ZERO,[Ca]:e.ONE,[Ra]:e.SRC_COLOR,[Aa]:e.SRC_ALPHA,[xa]:e.SRC_ALPHA_SATURATE,[Ta]:e.DST_COLOR,[Ma]:e.DST_ALPHA,[Ea]:e.ONE_MINUS_SRC_COLOR,[Sa]:e.ONE_MINUS_SRC_ALPHA,[ga]:e.ONE_MINUS_DST_COLOR,[va]:e.ONE_MINUS_DST_ALPHA,[_a]:e.CONSTANT_COLOR,[ma]:e.ONE_MINUS_CONSTANT_COLOR,[ha]:e.CONSTANT_ALPHA,[pa]:e.ONE_MINUS_CONSTANT_ALPHA};function m(v,re,$,le,Z,z,fe,Le,Ke,ke){if(v===wt){L===!0&&(ve(e.BLEND),L=!1);return}if(L===!1&&(oe(e.BLEND),L=!0),v!==Ua){if(v!==l||ke!==p){if((r!==Kt||_!==Kt)&&(e.blendEquation(e.FUNC_ADD),r=Kt,_=Kt),ke)switch(v){case fn:e.blendFuncSeparate(e.ONE,e.ONE_MINUS_SRC_ALPHA,e.ONE,e.ONE_MINUS_SRC_ALPHA);break;case di:e.blendFunc(e.ONE,e.ONE);break;case fi:e.blendFuncSeparate(e.ZERO,e.ONE_MINUS_SRC_COLOR,e.ZERO,e.ONE);break;case li:e.blendFuncSeparate(e.ZERO,e.SRC_COLOR,e.ZERO,e.SRC_ALPHA);break;default:console.error("THREE.WebGLState: Invalid blending: ",v);break}else switch(v){case fn:e.blendFuncSeparate(e.SRC_ALPHA,e.ONE_MINUS_SRC_ALPHA,e.ONE,e.ONE_MINUS_SRC_ALPHA);break;case di:e.blendFunc(e.SRC_ALPHA,e.ONE);break;case fi:e.blendFuncSeparate(e.ZERO,e.ONE_MINUS_SRC_COLOR,e.ZERO,e.ONE);break;case li:e.blendFunc(e.ZERO,e.SRC_COLOR);break;default:console.error("THREE.WebGLState: Invalid blending: ",v);break}U=null,x=null,H=null,P=null,y.set(0,0,0),G=0,l=v,p=ke}return}Z=Z||re,z=z||$,fe=fe||le,(re!==r||Z!==_)&&(e.blendEquationSeparate(Qe[re],Qe[Z]),r=re,_=Z),($!==U||le!==x||z!==H||fe!==P)&&(e.blendFuncSeparate(Be[$],Be[le],Be[z],Be[fe]),U=$,x=le,H=z,P=fe),(Le.equals(y)===!1||Ke!==G)&&(e.blendColor(Le.r,Le.g,Le.b,Ke),y.copy(Le),G=Ke),l=v,p=!1}function ot(v,re){v.side===Mt?ve(e.CULL_FACE):oe(e.CULL_FACE);let $=v.side===mt;re&&($=!$),Ge($),v.blending===fn&&v.transparent===!1?m(wt):m(v.blending,v.blendEquation,v.blendSrc,v.blendDst,v.blendEquationAlpha,v.blendSrcAlpha,v.blendDstAlpha,v.blendColor,v.blendAlpha,v.premultipliedAlpha),h.setFunc(v.depthFunc),h.setTest(v.depthTest),h.setMask(v.depthWrite),o.setMask(v.colorWrite);let le=v.stencilWrite;d.setTest(le),le&&(d.setMask(v.stencilWriteMask),d.setFunc(v.stencilFunc,v.stencilRef,v.stencilFuncMask),d.setOp(v.stencilFail,v.stencilZFail,v.stencilZPass)),ye(v.polygonOffset,v.polygonOffsetFactor,v.polygonOffsetUnits),v.alphaToCoverage===!0?oe(e.SAMPLE_ALPHA_TO_COVERAGE):ve(e.SAMPLE_ALPHA_TO_COVERAGE)}function Ge(v){f!==v&&(v?e.frontFace(e.CW):e.frontFace(e.CCW),f=v)}function Xe(v){v!==Pa?(oe(e.CULL_FACE),v!==R&&(v===ci?e.cullFace(e.BACK):v===La?e.cullFace(e.FRONT):e.cullFace(e.FRONT_AND_BACK))):ve(e.CULL_FACE),R=v}function pe(v){v!==Y&&(W&&e.lineWidth(v),Y=v)}function ye(v,re,$){v?(oe(e.POLYGON_OFFSET_FILL),(V!==re||K!==$)&&(e.polygonOffset(re,$),V=re,K=$)):ve(e.POLYGON_OFFSET_FILL)}function Ee(v){v?oe(e.SCISSOR_TEST):ve(e.SCISSOR_TEST)}function Ue(v){v===void 0&&(v=e.TEXTURE0+J-1),Se!==v&&(e.activeTexture(v),Se=v)}function nt(v,re,$){$===void 0&&(Se===null?$=e.TEXTURE0+J-1:$=Se);let le=Ae[$];le===void 0&&(le={type:void 0,texture:void 0},Ae[$]=le),(le.type!==v||le.texture!==re)&&(Se!==$&&(e.activeTexture($),Se=$),e.bindTexture(v,re||_e[v]),le.type=v,le.texture=re)}function u(){let v=Ae[Se];v!==void 0&&v.type!==void 0&&(e.bindTexture(v.type,null),v.type=void 0,v.texture=void 0)}function a(){try{e.compressedTexImage2D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function b(){try{e.compressedTexImage3D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function B(){try{e.texSubImage2D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function X(){try{e.texSubImage3D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function O(){try{e.compressedTexSubImage2D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function he(){try{e.compressedTexSubImage3D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function ie(){try{e.texStorage2D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function ue(){try{e.texStorage3D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function me(){try{e.texImage2D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function q(){try{e.texImage3D(...arguments)}catch(v){console.error("THREE.WebGLState:",v)}}function se(v){je.equals(v)===!1&&(e.scissor(v.x,v.y,v.z,v.w),je.copy(v))}function xe(v){k.equals(v)===!1&&(e.viewport(v.x,v.y,v.z,v.w),k.copy(v))}function Te(v,re){let $=M.get(re);$===void 0&&($=new WeakMap,M.set(re,$));let le=$.get(v);le===void 0&&(le=e.getUniformBlockIndex(re,v.name),$.set(v,le))}function te(v,re){let le=M.get(re).get(v);C.get(re)!==le&&(e.uniformBlockBinding(re,le,v.__bindingPointIndex),C.set(re,le))}function Pe(){e.disable(e.BLEND),e.disable(e.CULL_FACE),e.disable(e.DEPTH_TEST),e.disable(e.POLYGON_OFFSET_FILL),e.disable(e.SCISSOR_TEST),e.disable(e.STENCIL_TEST),e.disable(e.SAMPLE_ALPHA_TO_COVERAGE),e.blendEquation(e.FUNC_ADD),e.blendFunc(e.ONE,e.ZERO),e.blendFuncSeparate(e.ONE,e.ZERO,e.ONE,e.ZERO),e.blendColor(0,0,0,0),e.colorMask(!0,!0,!0,!0),e.clearColor(0,0,0,0),e.depthMask(!0),e.depthFunc(e.LESS),h.setReversed(!1),e.clearDepth(1),e.stencilMask(4294967295),e.stencilFunc(e.ALWAYS,0,4294967295),e.stencilOp(e.KEEP,e.KEEP,e.KEEP),e.clearStencil(0),e.cullFace(e.BACK),e.frontFace(e.CCW),e.polygonOffset(0,0),e.activeTexture(e.TEXTURE0),e.bindFramebuffer(e.FRAMEBUFFER,null),e.bindFramebuffer(e.DRAW_FRAMEBUFFER,null),e.bindFramebuffer(e.READ_FRAMEBUFFER,null),e.useProgram(null),e.lineWidth(1),e.scissor(0,0,e.canvas.width,e.canvas.height),e.viewport(0,0,e.canvas.width,e.canvas.height),D={},Se=null,Ae={},T={},g=new WeakMap,A=[],N=null,L=!1,l=null,r=null,U=null,x=null,_=null,H=null,P=null,y=new $e(0,0,0),G=0,p=!1,f=null,R=null,Y=null,V=null,K=null,je.set(0,0,e.canvas.width,e.canvas.height),k.set(0,0,e.canvas.width,e.canvas.height),o.reset(),h.reset(),d.reset()}return{buffers:{color:o,depth:h,stencil:d},enable:oe,disable:ve,bindFramebuffer:Fe,drawBuffers:Re,useProgram:Ze,setBlending:m,setMaterial:ot,setFlipSided:Ge,setCullFace:Xe,setLineWidth:pe,setPolygonOffset:ye,setScissorTest:Ee,activeTexture:Ue,bindTexture:nt,unbindTexture:u,compressedTexImage2D:a,compressedTexImage3D:b,texImage2D:me,texImage3D:q,updateUBOMapping:Te,uniformBlockBinding:te,texStorage2D:ie,texStorage3D:ue,texSubImage2D:B,texSubImage3D:X,compressedTexSubImage2D:O,compressedTexSubImage3D:he,scissor:se,viewport:xe,reset:Pe}}function wf(e,n,t,i,c,o,h){let d=n.has("WEBGL_multisampled_render_to_texture")?n.get("WEBGL_multisampled_render_to_texture"):null,C=typeof navigator>"u"?!1:/OculusBrowser/g.test(navigator.userAgent),M=new dt,D=new WeakMap,T,g=new WeakMap,A=!1;try{A=typeof OffscreenCanvas<"u"&&new OffscreenCanvas(1,1).getContext("2d")!==null}catch{}function N(u,a){return A?new OffscreenCanvas(u,a):Wa("canvas")}function L(u,a,b){let B=1,X=nt(u);if((X.width>b||X.height>b)&&(B=b/Math.max(X.width,X.height)),B<1)if(typeof HTMLImageElement<"u"&&u instanceof HTMLImageElement||typeof HTMLCanvasElement<"u"&&u instanceof HTMLCanvasElement||typeof ImageBitmap<"u"&&u instanceof ImageBitmap||typeof VideoFrame<"u"&&u instanceof VideoFrame){let O=Math.floor(B*X.width),he=Math.floor(B*X.height);T===void 0&&(T=N(O,he));let ie=a?N(O,he):T;return ie.width=O,ie.height=he,ie.getContext("2d").drawImage(u,0,0,O,he),console.warn("THREE.WebGLRenderer: Texture has been resized from ("+X.width+"x"+X.height+") to ("+O+"x"+he+")."),ie}else return"data"in u&&console.warn("THREE.WebGLRenderer: Image in DataTexture is too big ("+X.width+"x"+X.height+")."),u;return u}function l(u){return u.generateMipmaps}function r(u){e.generateMipmap(u)}function U(u){return u.isWebGLCubeRenderTarget?e.TEXTURE_CUBE_MAP:u.isWebGL3DRenderTarget?e.TEXTURE_3D:u.isWebGLArrayRenderTarget||u.isCompressedArrayTexture?e.TEXTURE_2D_ARRAY:e.TEXTURE_2D}function x(u,a,b,B,X=!1){if(u!==null){if(e[u]!==void 0)return e[u];console.warn("THREE.WebGLRenderer: Attempt to use non-existing WebGL internal format '"+u+"'")}let O=a;if(a===e.RED&&(b===e.FLOAT&&(O=e.R32F),b===e.HALF_FLOAT&&(O=e.R16F),b===e.UNSIGNED_BYTE&&(O=e.R8)),a===e.RED_INTEGER&&(b===e.UNSIGNED_BYTE&&(O=e.R8UI),b===e.UNSIGNED_SHORT&&(O=e.R16UI),b===e.UNSIGNED_INT&&(O=e.R32UI),b===e.BYTE&&(O=e.R8I),b===e.SHORT&&(O=e.R16I),b===e.INT&&(O=e.R32I)),a===e.RG&&(b===e.FLOAT&&(O=e.RG32F),b===e.HALF_FLOAT&&(O=e.RG16F),b===e.UNSIGNED_BYTE&&(O=e.RG8)),a===e.RG_INTEGER&&(b===e.UNSIGNED_BYTE&&(O=e.RG8UI),b===e.UNSIGNED_SHORT&&(O=e.RG16UI),b===e.UNSIGNED_INT&&(O=e.RG32UI),b===e.BYTE&&(O=e.RG8I),b===e.SHORT&&(O=e.RG16I),b===e.INT&&(O=e.RG32I)),a===e.RGB_INTEGER&&(b===e.UNSIGNED_BYTE&&(O=e.RGB8UI),b===e.UNSIGNED_SHORT&&(O=e.RGB16UI),b===e.UNSIGNED_INT&&(O=e.RGB32UI),b===e.BYTE&&(O=e.RGB8I),b===e.SHORT&&(O=e.RGB16I),b===e.INT&&(O=e.RGB32I)),a===e.RGBA_INTEGER&&(b===e.UNSIGNED_BYTE&&(O=e.RGBA8UI),b===e.UNSIGNED_SHORT&&(O=e.RGBA16UI),b===e.UNSIGNED_INT&&(O=e.RGBA32UI),b===e.BYTE&&(O=e.RGBA8I),b===e.SHORT&&(O=e.RGBA16I),b===e.INT&&(O=e.RGBA32I)),a===e.RGB&&b===e.UNSIGNED_INT_5_9_9_9_REV&&(O=e.RGB9_E5),a===e.RGBA){let he=X?Er:tt.getTransfer(B);b===e.FLOAT&&(O=e.RGBA32F),b===e.HALF_FLOAT&&(O=e.RGBA16F),b===e.UNSIGNED_BYTE&&(O=he===Ye?e.SRGB8_ALPHA8:e.RGBA8),b===e.UNSIGNED_SHORT_4_4_4_4&&(O=e.RGBA4),b===e.UNSIGNED_SHORT_5_5_5_1&&(O=e.RGB5_A1)}return(O===e.R16F||O===e.R32F||O===e.RG16F||O===e.RG32F||O===e.RGBA16F||O===e.RGBA32F)&&n.get("EXT_color_buffer_float"),O}function _(u,a){let b;return u?a===null||a===Jt||a===jt?b=e.DEPTH24_STENCIL8:a===Dt?b=e.DEPTH32F_STENCIL8:a===pn&&(b=e.DEPTH24_STENCIL8,console.warn("DepthTexture: 16 bit depth attachment is not supported with stencil. Using 24-bit attachment.")):a===null||a===Jt||a===jt?b=e.DEPTH_COMPONENT24:a===Dt?b=e.DEPTH_COMPONENT32F:a===pn&&(b=e.DEPTH_COMPONENT16),b}function H(u,a){return l(u)===!0||u.isFramebufferTexture&&u.minFilter!==$t&&u.minFilter!==Bt?Math.log2(Math.max(a.width,a.height))+1:u.mipmaps!==void 0&&u.mipmaps.length>0?u.mipmaps.length:u.isCompressedTexture&&Array.isArray(u.image)?a.mipmaps.length:1}function P(u){let a=u.target;a.removeEventListener("dispose",P),G(a),a.isVideoTexture&&D.delete(a)}function y(u){let a=u.target;a.removeEventListener("dispose",y),f(a)}function G(u){let a=i.get(u);if(a.__webglInit===void 0)return;let b=u.source,B=g.get(b);if(B){let X=B[a.__cacheKey];X.usedTimes--,X.usedTimes===0&&p(u),Object.keys(B).length===0&&g.delete(b)}i.remove(u)}function p(u){let a=i.get(u);e.deleteTexture(a.__webglTexture);let b=u.source,B=g.get(b);delete B[a.__cacheKey],h.memory.textures--}function f(u){let a=i.get(u);if(u.depthTexture&&(u.depthTexture.dispose(),i.remove(u.depthTexture)),u.isWebGLCubeRenderTarget)for(let B=0;B<6;B++){if(Array.isArray(a.__webglFramebuffer[B]))for(let X=0;X<a.__webglFramebuffer[B].length;X++)e.deleteFramebuffer(a.__webglFramebuffer[B][X]);else e.deleteFramebuffer(a.__webglFramebuffer[B]);a.__webglDepthbuffer&&e.deleteRenderbuffer(a.__webglDepthbuffer[B])}else{if(Array.isArray(a.__webglFramebuffer))for(let B=0;B<a.__webglFramebuffer.length;B++)e.deleteFramebuffer(a.__webglFramebuffer[B]);else e.deleteFramebuffer(a.__webglFramebuffer);if(a.__webglDepthbuffer&&e.deleteRenderbuffer(a.__webglDepthbuffer),a.__webglMultisampledFramebuffer&&e.deleteFramebuffer(a.__webglMultisampledFramebuffer),a.__webglColorRenderbuffer)for(let B=0;B<a.__webglColorRenderbuffer.length;B++)a.__webglColorRenderbuffer[B]&&e.deleteRenderbuffer(a.__webglColorRenderbuffer[B]);a.__webglDepthRenderbuffer&&e.deleteRenderbuffer(a.__webglDepthRenderbuffer)}let b=u.textures;for(let B=0,X=b.length;B<X;B++){let O=i.get(b[B]);O.__webglTexture&&(e.deleteTexture(O.__webglTexture),h.memory.textures--),i.remove(b[B])}i.remove(u)}let R=0;function Y(){R=0}function V(){let u=R;return u>=c.maxTextures&&console.warn("THREE.WebGLTextures: Trying to use "+u+" texture units while this GPU supports only "+c.maxTextures),R+=1,u}function K(u){let a=[];return a.push(u.wrapS),a.push(u.wrapT),a.push(u.wrapR||0),a.push(u.magFilter),a.push(u.minFilter),a.push(u.anisotropy),a.push(u.internalFormat),a.push(u.format),a.push(u.type),a.push(u.generateMipmaps),a.push(u.premultiplyAlpha),a.push(u.flipY),a.push(u.unpackAlignment),a.push(u.colorSpace),a.join()}function J(u,a){let b=i.get(u);if(u.isVideoTexture&&Ee(u),u.isRenderTargetTexture===!1&&u.version>0&&b.__version!==u.version){let B=u.image;if(B===null)console.warn("THREE.WebGLRenderer: Texture marked for update but no image data found.");else if(B.complete===!1)console.warn("THREE.WebGLRenderer: Texture marked for update but image is incomplete");else{_e(b,u,a);return}}t.bindTexture(e.TEXTURE_2D,b.__webglTexture,e.TEXTURE0+a)}function W(u,a){let b=i.get(u);if(u.version>0&&b.__version!==u.version){_e(b,u,a);return}t.bindTexture(e.TEXTURE_2D_ARRAY,b.__webglTexture,e.TEXTURE0+a)}function ee(u,a){let b=i.get(u);if(u.version>0&&b.__version!==u.version){_e(b,u,a);return}t.bindTexture(e.TEXTURE_3D,b.__webglTexture,e.TEXTURE0+a)}function F(u,a){let b=i.get(u);if(u.version>0&&b.__version!==u.version){oe(b,u,a);return}t.bindTexture(e.TEXTURE_CUBE_MAP,b.__webglTexture,e.TEXTURE0+a)}let Se={[Na]:e.REPEAT,[ya]:e.CLAMP_TO_EDGE,[Ia]:e.MIRRORED_REPEAT},Ae={[$t]:e.NEAREST,[Oa]:e.NEAREST_MIPMAP_NEAREST,[nn]:e.NEAREST_MIPMAP_LINEAR,[Bt]:e.LINEAR,[Mn]:e.LINEAR_MIPMAP_NEAREST,[Yt]:e.LINEAR_MIPMAP_LINEAR},we={[za]:e.NEVER,[ka]:e.ALWAYS,[Va]:e.LESS,[_r]:e.LEQUAL,[Ha]:e.EQUAL,[Ga]:e.GEQUAL,[Ba]:e.GREATER,[Fa]:e.NOTEQUAL};function He(u,a){if(a.type===Dt&&n.has("OES_texture_float_linear")===!1&&(a.magFilter===Bt||a.magFilter===Mn||a.magFilter===nn||a.magFilter===Yt||a.minFilter===Bt||a.minFilter===Mn||a.minFilter===nn||a.minFilter===Yt)&&console.warn("THREE.WebGLRenderer: Unable to use linear filtering with floating point textures. OES_texture_float_linear not supported on this device."),e.texParameteri(u,e.TEXTURE_WRAP_S,Se[a.wrapS]),e.texParameteri(u,e.TEXTURE_WRAP_T,Se[a.wrapT]),(u===e.TEXTURE_3D||u===e.TEXTURE_2D_ARRAY)&&e.texParameteri(u,e.TEXTURE_WRAP_R,Se[a.wrapR]),e.texParameteri(u,e.TEXTURE_MAG_FILTER,Ae[a.magFilter]),e.texParameteri(u,e.TEXTURE_MIN_FILTER,Ae[a.minFilter]),a.compareFunction&&(e.texParameteri(u,e.TEXTURE_COMPARE_MODE,e.COMPARE_REF_TO_TEXTURE),e.texParameteri(u,e.TEXTURE_COMPARE_FUNC,we[a.compareFunction])),n.has("EXT_texture_filter_anisotropic")===!0){if(a.magFilter===$t||a.minFilter!==nn&&a.minFilter!==Yt||a.type===Dt&&n.has("OES_texture_float_linear")===!1)return;if(a.anisotropy>1||i.get(a).__currentAnisotropy){let b=n.get("EXT_texture_filter_anisotropic");e.texParameterf(u,b.TEXTURE_MAX_ANISOTROPY_EXT,Math.min(a.anisotropy,c.getMaxAnisotropy())),i.get(a).__currentAnisotropy=a.anisotropy}}}function je(u,a){let b=!1;u.__webglInit===void 0&&(u.__webglInit=!0,a.addEventListener("dispose",P));let B=a.source,X=g.get(B);X===void 0&&(X={},g.set(B,X));let O=K(a);if(O!==u.__cacheKey){X[O]===void 0&&(X[O]={texture:e.createTexture(),usedTimes:0},h.memory.textures++,b=!0),X[O].usedTimes++;let he=X[u.__cacheKey];he!==void 0&&(X[u.__cacheKey].usedTimes--,he.usedTimes===0&&p(a)),u.__cacheKey=O,u.__webglTexture=X[O].texture}return b}function k(u,a,b){return Math.floor(Math.floor(u/b)/a)}function j(u,a,b,B){let O=u.updateRanges;if(O.length===0)t.texSubImage2D(e.TEXTURE_2D,0,0,0,a.width,a.height,b,B,a.data);else{O.sort((q,se)=>q.start-se.start);let he=0;for(let q=1;q<O.length;q++){let se=O[he],xe=O[q],Te=se.start+se.count,te=k(xe.start,a.width,4),Pe=k(se.start,a.width,4);xe.start<=Te+1&&te===Pe&&k(xe.start+xe.count-1,a.width,4)===te?se.count=Math.max(se.count,xe.start+xe.count-se.start):(++he,O[he]=xe)}O.length=he+1;let ie=e.getParameter(e.UNPACK_ROW_LENGTH),ue=e.getParameter(e.UNPACK_SKIP_PIXELS),me=e.getParameter(e.UNPACK_SKIP_ROWS);e.pixelStorei(e.UNPACK_ROW_LENGTH,a.width);for(let q=0,se=O.length;q<se;q++){let xe=O[q],Te=Math.floor(xe.start/4),te=Math.ceil(xe.count/4),Pe=Te%a.width,v=Math.floor(Te/a.width),re=te,$=1;e.pixelStorei(e.UNPACK_SKIP_PIXELS,Pe),e.pixelStorei(e.UNPACK_SKIP_ROWS,v),t.texSubImage2D(e.TEXTURE_2D,0,Pe,v,re,$,b,B,a.data)}u.clearUpdateRanges(),e.pixelStorei(e.UNPACK_ROW_LENGTH,ie),e.pixelStorei(e.UNPACK_SKIP_PIXELS,ue),e.pixelStorei(e.UNPACK_SKIP_ROWS,me)}}function _e(u,a,b){let B=e.TEXTURE_2D;(a.isDataArrayTexture||a.isCompressedArrayTexture)&&(B=e.TEXTURE_2D_ARRAY),a.isData3DTexture&&(B=e.TEXTURE_3D);let X=je(u,a),O=a.source;t.bindTexture(B,u.__webglTexture,e.TEXTURE0+b);let he=i.get(O);if(O.version!==he.__version||X===!0){t.activeTexture(e.TEXTURE0+b);let ie=tt.getPrimaries(tt.workingColorSpace),ue=a.colorSpace===Ft?null:tt.getPrimaries(a.colorSpace),me=a.colorSpace===Ft||ie===ue?e.NONE:e.BROWSER_DEFAULT_WEBGL;e.pixelStorei(e.UNPACK_FLIP_Y_WEBGL,a.flipY),e.pixelStorei(e.UNPACK_PREMULTIPLY_ALPHA_WEBGL,a.premultiplyAlpha),e.pixelStorei(e.UNPACK_ALIGNMENT,a.unpackAlignment),e.pixelStorei(e.UNPACK_COLORSPACE_CONVERSION_WEBGL,me);let q=L(a.image,!1,c.maxTextureSize);q=Ue(a,q);let se=o.convert(a.format,a.colorSpace),xe=o.convert(a.type),Te=x(a.internalFormat,se,xe,a.colorSpace,a.isVideoTexture);He(B,a);let te,Pe=a.mipmaps,v=a.isVideoTexture!==!0,re=he.__version===void 0||X===!0,$=O.dataReady,le=H(a,q);if(a.isDepthTexture)Te=_(a.format===un,a.type),re&&(v?t.texStorage2D(e.TEXTURE_2D,1,Te,q.width,q.height):t.texImage2D(e.TEXTURE_2D,0,Te,q.width,q.height,0,se,xe,null));else if(a.isDataTexture)if(Pe.length>0){v&&re&&t.texStorage2D(e.TEXTURE_2D,le,Te,Pe[0].width,Pe[0].height);for(let Z=0,z=Pe.length;Z<z;Z++)te=Pe[Z],v?$&&t.texSubImage2D(e.TEXTURE_2D,Z,0,0,te.width,te.height,se,xe,te.data):t.texImage2D(e.TEXTURE_2D,Z,Te,te.width,te.height,0,se,xe,te.data);a.generateMipmaps=!1}else v?(re&&t.texStorage2D(e.TEXTURE_2D,le,Te,q.width,q.height),$&&j(a,q,se,xe)):t.texImage2D(e.TEXTURE_2D,0,Te,q.width,q.height,0,se,xe,q.data);else if(a.isCompressedTexture)if(a.isCompressedArrayTexture){v&&re&&t.texStorage3D(e.TEXTURE_2D_ARRAY,le,Te,Pe[0].width,Pe[0].height,q.depth);for(let Z=0,z=Pe.length;Z<z;Z++)if(te=Pe[Z],a.format!==Tt)if(se!==null)if(v){if($)if(a.layerUpdates.size>0){let fe=ui(te.width,te.height,a.format,a.type);for(let Le of a.layerUpdates){let Ke=te.data.subarray(Le*fe/te.data.BYTES_PER_ELEMENT,(Le+1)*fe/te.data.BYTES_PER_ELEMENT);t.compressedTexSubImage3D(e.TEXTURE_2D_ARRAY,Z,0,0,Le,te.width,te.height,1,se,Ke)}a.clearLayerUpdates()}else t.compressedTexSubImage3D(e.TEXTURE_2D_ARRAY,Z,0,0,0,te.width,te.height,q.depth,se,te.data)}else t.compressedTexImage3D(e.TEXTURE_2D_ARRAY,Z,Te,te.width,te.height,q.depth,0,te.data,0,0);else console.warn("THREE.WebGLRenderer: Attempt to load unsupported compressed texture format in .uploadTexture()");else v?$&&t.texSubImage3D(e.TEXTURE_2D_ARRAY,Z,0,0,0,te.width,te.height,q.depth,se,xe,te.data):t.texImage3D(e.TEXTURE_2D_ARRAY,Z,Te,te.width,te.height,q.depth,0,se,xe,te.data)}else{v&&re&&t.texStorage2D(e.TEXTURE_2D,le,Te,Pe[0].width,Pe[0].height);for(let Z=0,z=Pe.length;Z<z;Z++)te=Pe[Z],a.format!==Tt?se!==null?v?$&&t.compressedTexSubImage2D(e.TEXTURE_2D,Z,0,0,te.width,te.height,se,te.data):t.compressedTexImage2D(e.TEXTURE_2D,Z,Te,te.width,te.height,0,te.data):console.warn("THREE.WebGLRenderer: Attempt to load unsupported compressed texture format in .uploadTexture()"):v?$&&t.texSubImage2D(e.TEXTURE_2D,Z,0,0,te.width,te.height,se,xe,te.data):t.texImage2D(e.TEXTURE_2D,Z,Te,te.width,te.height,0,se,xe,te.data)}else if(a.isDataArrayTexture)if(v){if(re&&t.texStorage3D(e.TEXTURE_2D_ARRAY,le,Te,q.width,q.height,q.depth),$)if(a.layerUpdates.size>0){let Z=ui(q.width,q.height,a.format,a.type);for(let z of a.layerUpdates){let fe=q.data.subarray(z*Z/q.data.BYTES_PER_ELEMENT,(z+1)*Z/q.data.BYTES_PER_ELEMENT);t.texSubImage3D(e.TEXTURE_2D_ARRAY,0,0,0,z,q.width,q.height,1,se,xe,fe)}a.clearLayerUpdates()}else t.texSubImage3D(e.TEXTURE_2D_ARRAY,0,0,0,0,q.width,q.height,q.depth,se,xe,q.data)}else t.texImage3D(e.TEXTURE_2D_ARRAY,0,Te,q.width,q.height,q.depth,0,se,xe,q.data);else if(a.isData3DTexture)v?(re&&t.texStorage3D(e.TEXTURE_3D,le,Te,q.width,q.height,q.depth),$&&t.texSubImage3D(e.TEXTURE_3D,0,0,0,0,q.width,q.height,q.depth,se,xe,q.data)):t.texImage3D(e.TEXTURE_3D,0,Te,q.width,q.height,q.depth,0,se,xe,q.data);else if(a.isFramebufferTexture){if(re)if(v)t.texStorage2D(e.TEXTURE_2D,le,Te,q.width,q.height);else{let Z=q.width,z=q.height;for(let fe=0;fe<le;fe++)t.texImage2D(e.TEXTURE_2D,fe,Te,Z,z,0,se,xe,null),Z>>=1,z>>=1}}else if(Pe.length>0){if(v&&re){let Z=nt(Pe[0]);t.texStorage2D(e.TEXTURE_2D,le,Te,Z.width,Z.height)}for(let Z=0,z=Pe.length;Z<z;Z++)te=Pe[Z],v?$&&t.texSubImage2D(e.TEXTURE_2D,Z,0,0,se,xe,te):t.texImage2D(e.TEXTURE_2D,Z,Te,se,xe,te);a.generateMipmaps=!1}else if(v){if(re){let Z=nt(q);t.texStorage2D(e.TEXTURE_2D,le,Te,Z.width,Z.height)}$&&t.texSubImage2D(e.TEXTURE_2D,0,0,0,se,xe,q)}else t.texImage2D(e.TEXTURE_2D,0,Te,se,xe,q);l(a)&&r(B),he.__version=O.version,a.onUpdate&&a.onUpdate(a)}u.__version=a.version}function oe(u,a,b){if(a.image.length!==6)return;let B=je(u,a),X=a.source;t.bindTexture(e.TEXTURE_CUBE_MAP,u.__webglTexture,e.TEXTURE0+b);let O=i.get(X);if(X.version!==O.__version||B===!0){t.activeTexture(e.TEXTURE0+b);let he=tt.getPrimaries(tt.workingColorSpace),ie=a.colorSpace===Ft?null:tt.getPrimaries(a.colorSpace),ue=a.colorSpace===Ft||he===ie?e.NONE:e.BROWSER_DEFAULT_WEBGL;e.pixelStorei(e.UNPACK_FLIP_Y_WEBGL,a.flipY),e.pixelStorei(e.UNPACK_PREMULTIPLY_ALPHA_WEBGL,a.premultiplyAlpha),e.pixelStorei(e.UNPACK_ALIGNMENT,a.unpackAlignment),e.pixelStorei(e.UNPACK_COLORSPACE_CONVERSION_WEBGL,ue);let me=a.isCompressedTexture||a.image[0].isCompressedTexture,q=a.image[0]&&a.image[0].isDataTexture,se=[];for(let z=0;z<6;z++)!me&&!q?se[z]=L(a.image[z],!0,c.maxCubemapSize):se[z]=q?a.image[z].image:a.image[z],se[z]=Ue(a,se[z]);let xe=se[0],Te=o.convert(a.format,a.colorSpace),te=o.convert(a.type),Pe=x(a.internalFormat,Te,te,a.colorSpace),v=a.isVideoTexture!==!0,re=O.__version===void 0||B===!0,$=X.dataReady,le=H(a,xe);He(e.TEXTURE_CUBE_MAP,a);let Z;if(me){v&&re&&t.texStorage2D(e.TEXTURE_CUBE_MAP,le,Pe,xe.width,xe.height);for(let z=0;z<6;z++){Z=se[z].mipmaps;for(let fe=0;fe<Z.length;fe++){let Le=Z[fe];a.format!==Tt?Te!==null?v?$&&t.compressedTexSubImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe,0,0,Le.width,Le.height,Te,Le.data):t.compressedTexImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe,Pe,Le.width,Le.height,0,Le.data):console.warn("THREE.WebGLRenderer: Attempt to load unsupported compressed texture format in .setTextureCube()"):v?$&&t.texSubImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe,0,0,Le.width,Le.height,Te,te,Le.data):t.texImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe,Pe,Le.width,Le.height,0,Te,te,Le.data)}}}else{if(Z=a.mipmaps,v&&re){Z.length>0&&le++;let z=nt(se[0]);t.texStorage2D(e.TEXTURE_CUBE_MAP,le,Pe,z.width,z.height)}for(let z=0;z<6;z++)if(q){v?$&&t.texSubImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,0,0,0,se[z].width,se[z].height,Te,te,se[z].data):t.texImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,0,Pe,se[z].width,se[z].height,0,Te,te,se[z].data);for(let fe=0;fe<Z.length;fe++){let Ke=Z[fe].image[z].image;v?$&&t.texSubImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe+1,0,0,Ke.width,Ke.height,Te,te,Ke.data):t.texImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe+1,Pe,Ke.width,Ke.height,0,Te,te,Ke.data)}}else{v?$&&t.texSubImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,0,0,0,Te,te,se[z]):t.texImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,0,Pe,Te,te,se[z]);for(let fe=0;fe<Z.length;fe++){let Le=Z[fe];v?$&&t.texSubImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe+1,0,0,Te,te,Le.image[z]):t.texImage2D(e.TEXTURE_CUBE_MAP_POSITIVE_X+z,fe+1,Pe,Te,te,Le.image[z])}}}l(a)&&r(e.TEXTURE_CUBE_MAP),O.__version=X.version,a.onUpdate&&a.onUpdate(a)}u.__version=a.version}function ve(u,a,b,B,X,O){let he=o.convert(b.format,b.colorSpace),ie=o.convert(b.type),ue=x(b.internalFormat,he,ie,b.colorSpace),me=i.get(a),q=i.get(b);if(q.__renderTarget=a,!me.__hasExternalTextures){let se=Math.max(1,a.width>>O),xe=Math.max(1,a.height>>O);X===e.TEXTURE_3D||X===e.TEXTURE_2D_ARRAY?t.texImage3D(X,O,ue,se,xe,a.depth,0,he,ie,null):t.texImage2D(X,O,ue,se,xe,0,he,ie,null)}t.bindFramebuffer(e.FRAMEBUFFER,u),ye(a)?d.framebufferTexture2DMultisampleEXT(e.FRAMEBUFFER,B,X,q.__webglTexture,0,pe(a)):(X===e.TEXTURE_2D||X>=e.TEXTURE_CUBE_MAP_POSITIVE_X&&X<=e.TEXTURE_CUBE_MAP_NEGATIVE_Z)&&e.framebufferTexture2D(e.FRAMEBUFFER,B,X,q.__webglTexture,O),t.bindFramebuffer(e.FRAMEBUFFER,null)}function Fe(u,a,b){if(e.bindRenderbuffer(e.RENDERBUFFER,u),a.depthBuffer){let B=a.depthTexture,X=B&&B.isDepthTexture?B.type:null,O=_(a.stencilBuffer,X),he=a.stencilBuffer?e.DEPTH_STENCIL_ATTACHMENT:e.DEPTH_ATTACHMENT,ie=pe(a);ye(a)?d.renderbufferStorageMultisampleEXT(e.RENDERBUFFER,ie,O,a.width,a.height):b?e.renderbufferStorageMultisample(e.RENDERBUFFER,ie,O,a.width,a.height):e.renderbufferStorage(e.RENDERBUFFER,O,a.width,a.height),e.framebufferRenderbuffer(e.FRAMEBUFFER,he,e.RENDERBUFFER,u)}else{let B=a.textures;for(let X=0;X<B.length;X++){let O=B[X],he=o.convert(O.format,O.colorSpace),ie=o.convert(O.type),ue=x(O.internalFormat,he,ie,O.colorSpace),me=pe(a);b&&ye(a)===!1?e.renderbufferStorageMultisample(e.RENDERBUFFER,me,ue,a.width,a.height):ye(a)?d.renderbufferStorageMultisampleEXT(e.RENDERBUFFER,me,ue,a.width,a.height):e.renderbufferStorage(e.RENDERBUFFER,ue,a.width,a.height)}}e.bindRenderbuffer(e.RENDERBUFFER,null)}function Re(u,a){if(a&&a.isWebGLCubeRenderTarget)throw new Error("Depth Texture with cube render targets is not supported");if(t.bindFramebuffer(e.FRAMEBUFFER,u),!(a.depthTexture&&a.depthTexture.isDepthTexture))throw new Error("renderTarget.depthTexture must be an instance of THREE.DepthTexture");let B=i.get(a.depthTexture);B.__renderTarget=a,(!B.__webglTexture||a.depthTexture.image.width!==a.width||a.depthTexture.image.height!==a.height)&&(a.depthTexture.image.width=a.width,a.depthTexture.image.height=a.height,a.depthTexture.needsUpdate=!0),J(a.depthTexture,0);let X=B.__webglTexture,O=pe(a);if(a.depthTexture.format===Qn)ye(a)?d.framebufferTexture2DMultisampleEXT(e.FRAMEBUFFER,e.DEPTH_ATTACHMENT,e.TEXTURE_2D,X,0,O):e.framebufferTexture2D(e.FRAMEBUFFER,e.DEPTH_ATTACHMENT,e.TEXTURE_2D,X,0);else if(a.depthTexture.format===un)ye(a)?d.framebufferTexture2DMultisampleEXT(e.FRAMEBUFFER,e.DEPTH_STENCIL_ATTACHMENT,e.TEXTURE_2D,X,0,O):e.framebufferTexture2D(e.FRAMEBUFFER,e.DEPTH_STENCIL_ATTACHMENT,e.TEXTURE_2D,X,0);else throw new Error("Unknown depthTexture format")}function Ze(u){let a=i.get(u),b=u.isWebGLCubeRenderTarget===!0;if(a.__boundDepthTexture!==u.depthTexture){let B=u.depthTexture;if(a.__depthDisposeCallback&&a.__depthDisposeCallback(),B){let X=()=>{delete a.__boundDepthTexture,delete a.__depthDisposeCallback,B.removeEventListener("dispose",X)};B.addEventListener("dispose",X),a.__depthDisposeCallback=X}a.__boundDepthTexture=B}if(u.depthTexture&&!a.__autoAllocateDepthBuffer){if(b)throw new Error("target.depthTexture not supported in Cube render targets");let B=u.texture.mipmaps;B&&B.length>0?Re(a.__webglFramebuffer[0],u):Re(a.__webglFramebuffer,u)}else if(b){a.__webglDepthbuffer=[];for(let B=0;B<6;B++)if(t.bindFramebuffer(e.FRAMEBUFFER,a.__webglFramebuffer[B]),a.__webglDepthbuffer[B]===void 0)a.__webglDepthbuffer[B]=e.createRenderbuffer(),Fe(a.__webglDepthbuffer[B],u,!1);else{let X=u.stencilBuffer?e.DEPTH_STENCIL_ATTACHMENT:e.DEPTH_ATTACHMENT,O=a.__webglDepthbuffer[B];e.bindRenderbuffer(e.RENDERBUFFER,O),e.framebufferRenderbuffer(e.FRAMEBUFFER,X,e.RENDERBUFFER,O)}}else{let B=u.texture.mipmaps;if(B&&B.length>0?t.bindFramebuffer(e.FRAMEBUFFER,a.__webglFramebuffer[0]):t.bindFramebuffer(e.FRAMEBUFFER,a.__webglFramebuffer),a.__webglDepthbuffer===void 0)a.__webglDepthbuffer=e.createRenderbuffer(),Fe(a.__webglDepthbuffer,u,!1);else{let X=u.stencilBuffer?e.DEPTH_STENCIL_ATTACHMENT:e.DEPTH_ATTACHMENT,O=a.__webglDepthbuffer;e.bindRenderbuffer(e.RENDERBUFFER,O),e.framebufferRenderbuffer(e.FRAMEBUFFER,X,e.RENDERBUFFER,O)}}t.bindFramebuffer(e.FRAMEBUFFER,null)}function Qe(u,a,b){let B=i.get(u);a!==void 0&&ve(B.__webglFramebuffer,u,u.texture,e.COLOR_ATTACHMENT0,e.TEXTURE_2D,0),b!==void 0&&Ze(u)}function Be(u){let a=u.texture,b=i.get(u),B=i.get(a);u.addEventListener("dispose",y);let X=u.textures,O=u.isWebGLCubeRenderTarget===!0,he=X.length>1;if(he||(B.__webglTexture===void 0&&(B.__webglTexture=e.createTexture()),B.__version=a.version,h.memory.textures++),O){b.__webglFramebuffer=[];for(let ie=0;ie<6;ie++)if(a.mipmaps&&a.mipmaps.length>0){b.__webglFramebuffer[ie]=[];for(let ue=0;ue<a.mipmaps.length;ue++)b.__webglFramebuffer[ie][ue]=e.createFramebuffer()}else b.__webglFramebuffer[ie]=e.createFramebuffer()}else{if(a.mipmaps&&a.mipmaps.length>0){b.__webglFramebuffer=[];for(let ie=0;ie<a.mipmaps.length;ie++)b.__webglFramebuffer[ie]=e.createFramebuffer()}else b.__webglFramebuffer=e.createFramebuffer();if(he)for(let ie=0,ue=X.length;ie<ue;ie++){let me=i.get(X[ie]);me.__webglTexture===void 0&&(me.__webglTexture=e.createTexture(),h.memory.textures++)}if(u.samples>0&&ye(u)===!1){b.__webglMultisampledFramebuffer=e.createFramebuffer(),b.__webglColorRenderbuffer=[],t.bindFramebuffer(e.FRAMEBUFFER,b.__webglMultisampledFramebuffer);for(let ie=0;ie<X.length;ie++){let ue=X[ie];b.__webglColorRenderbuffer[ie]=e.createRenderbuffer(),e.bindRenderbuffer(e.RENDERBUFFER,b.__webglColorRenderbuffer[ie]);let me=o.convert(ue.format,ue.colorSpace),q=o.convert(ue.type),se=x(ue.internalFormat,me,q,ue.colorSpace,u.isXRRenderTarget===!0),xe=pe(u);e.renderbufferStorageMultisample(e.RENDERBUFFER,xe,se,u.width,u.height),e.framebufferRenderbuffer(e.FRAMEBUFFER,e.COLOR_ATTACHMENT0+ie,e.RENDERBUFFER,b.__webglColorRenderbuffer[ie])}e.bindRenderbuffer(e.RENDERBUFFER,null),u.depthBuffer&&(b.__webglDepthRenderbuffer=e.createRenderbuffer(),Fe(b.__webglDepthRenderbuffer,u,!0)),t.bindFramebuffer(e.FRAMEBUFFER,null)}}if(O){t.bindTexture(e.TEXTURE_CUBE_MAP,B.__webglTexture),He(e.TEXTURE_CUBE_MAP,a);for(let ie=0;ie<6;ie++)if(a.mipmaps&&a.mipmaps.length>0)for(let ue=0;ue<a.mipmaps.length;ue++)ve(b.__webglFramebuffer[ie][ue],u,a,e.COLOR_ATTACHMENT0,e.TEXTURE_CUBE_MAP_POSITIVE_X+ie,ue);else ve(b.__webglFramebuffer[ie],u,a,e.COLOR_ATTACHMENT0,e.TEXTURE_CUBE_MAP_POSITIVE_X+ie,0);l(a)&&r(e.TEXTURE_CUBE_MAP),t.unbindTexture()}else if(he){for(let ie=0,ue=X.length;ie<ue;ie++){let me=X[ie],q=i.get(me);t.bindTexture(e.TEXTURE_2D,q.__webglTexture),He(e.TEXTURE_2D,me),ve(b.__webglFramebuffer,u,me,e.COLOR_ATTACHMENT0+ie,e.TEXTURE_2D,0),l(me)&&r(e.TEXTURE_2D)}t.unbindTexture()}else{let ie=e.TEXTURE_2D;if((u.isWebGL3DRenderTarget||u.isWebGLArrayRenderTarget)&&(ie=u.isWebGL3DRenderTarget?e.TEXTURE_3D:e.TEXTURE_2D_ARRAY),t.bindTexture(ie,B.__webglTexture),He(ie,a),a.mipmaps&&a.mipmaps.length>0)for(let ue=0;ue<a.mipmaps.length;ue++)ve(b.__webglFramebuffer[ue],u,a,e.COLOR_ATTACHMENT0,ie,ue);else ve(b.__webglFramebuffer,u,a,e.COLOR_ATTACHMENT0,ie,0);l(a)&&r(ie),t.unbindTexture()}u.depthBuffer&&Ze(u)}function m(u){let a=u.textures;for(let b=0,B=a.length;b<B;b++){let X=a[b];if(l(X)){let O=U(u),he=i.get(X).__webglTexture;t.bindTexture(O,he),r(O),t.unbindTexture()}}}let ot=[],Ge=[];function Xe(u){if(u.samples>0){if(ye(u)===!1){let a=u.textures,b=u.width,B=u.height,X=e.COLOR_BUFFER_BIT,O=u.stencilBuffer?e.DEPTH_STENCIL_ATTACHMENT:e.DEPTH_ATTACHMENT,he=i.get(u),ie=a.length>1;if(ie)for(let me=0;me<a.length;me++)t.bindFramebuffer(e.FRAMEBUFFER,he.__webglMultisampledFramebuffer),e.framebufferRenderbuffer(e.FRAMEBUFFER,e.COLOR_ATTACHMENT0+me,e.RENDERBUFFER,null),t.bindFramebuffer(e.FRAMEBUFFER,he.__webglFramebuffer),e.framebufferTexture2D(e.DRAW_FRAMEBUFFER,e.COLOR_ATTACHMENT0+me,e.TEXTURE_2D,null,0);t.bindFramebuffer(e.READ_FRAMEBUFFER,he.__webglMultisampledFramebuffer);let ue=u.texture.mipmaps;ue&&ue.length>0?t.bindFramebuffer(e.DRAW_FRAMEBUFFER,he.__webglFramebuffer[0]):t.bindFramebuffer(e.DRAW_FRAMEBUFFER,he.__webglFramebuffer);for(let me=0;me<a.length;me++){if(u.resolveDepthBuffer&&(u.depthBuffer&&(X|=e.DEPTH_BUFFER_BIT),u.stencilBuffer&&u.resolveStencilBuffer&&(X|=e.STENCIL_BUFFER_BIT)),ie){e.framebufferRenderbuffer(e.READ_FRAMEBUFFER,e.COLOR_ATTACHMENT0,e.RENDERBUFFER,he.__webglColorRenderbuffer[me]);let q=i.get(a[me]).__webglTexture;e.framebufferTexture2D(e.DRAW_FRAMEBUFFER,e.COLOR_ATTACHMENT0,e.TEXTURE_2D,q,0)}e.blitFramebuffer(0,0,b,B,0,0,b,B,X,e.NEAREST),C===!0&&(ot.length=0,Ge.length=0,ot.push(e.COLOR_ATTACHMENT0+me),u.depthBuffer&&u.resolveDepthBuffer===!1&&(ot.push(O),Ge.push(O),e.invalidateFramebuffer(e.DRAW_FRAMEBUFFER,Ge)),e.invalidateFramebuffer(e.READ_FRAMEBUFFER,ot))}if(t.bindFramebuffer(e.READ_FRAMEBUFFER,null),t.bindFramebuffer(e.DRAW_FRAMEBUFFER,null),ie)for(let me=0;me<a.length;me++){t.bindFramebuffer(e.FRAMEBUFFER,he.__webglMultisampledFramebuffer),e.framebufferRenderbuffer(e.FRAMEBUFFER,e.COLOR_ATTACHMENT0+me,e.RENDERBUFFER,he.__webglColorRenderbuffer[me]);let q=i.get(a[me]).__webglTexture;t.bindFramebuffer(e.FRAMEBUFFER,he.__webglFramebuffer),e.framebufferTexture2D(e.DRAW_FRAMEBUFFER,e.COLOR_ATTACHMENT0+me,e.TEXTURE_2D,q,0)}t.bindFramebuffer(e.DRAW_FRAMEBUFFER,he.__webglMultisampledFramebuffer)}else if(u.depthBuffer&&u.resolveDepthBuffer===!1&&C){let a=u.stencilBuffer?e.DEPTH_STENCIL_ATTACHMENT:e.DEPTH_ATTACHMENT;e.invalidateFramebuffer(e.DRAW_FRAMEBUFFER,[a])}}}function pe(u){return Math.min(c.maxSamples,u.samples)}function ye(u){let a=i.get(u);return u.samples>0&&n.has("WEBGL_multisampled_render_to_texture")===!0&&a.__useRenderToTexture!==!1}function Ee(u){let a=h.render.frame;D.get(u)!==a&&(D.set(u,a),u.update())}function Ue(u,a){let b=u.colorSpace,B=u.format,X=u.type;return u.isCompressedTexture===!0||u.isVideoTexture===!0||b!==vn&&b!==Ft&&(tt.getTransfer(b)===Ye?(B!==Tt||X!==yt)&&console.warn("THREE.WebGLTextures: sRGB encoded textures have to use RGBAFormat and UnsignedByteType."):console.error("THREE.WebGLTextures: Unsupported texture color space:",b)),a}function nt(u){return typeof HTMLImageElement<"u"&&u instanceof HTMLImageElement?(M.width=u.naturalWidth||u.width,M.height=u.naturalHeight||u.height):typeof VideoFrame<"u"&&u instanceof VideoFrame?(M.width=u.displayWidth,M.height=u.displayHeight):(M.width=u.width,M.height=u.height),M}this.allocateTextureUnit=V,this.resetTextureUnits=Y,this.setTexture2D=J,this.setTexture2DArray=W,this.setTexture3D=ee,this.setTextureCube=F,this.rebindTextures=Qe,this.setupRenderTarget=Be,this.updateRenderTargetMipmap=m,this.updateMultisampleRenderTarget=Xe,this.setupDepthRenderbuffer=Ze,this.setupFrameBufferTexture=ve,this.useMultisampledRTT=ye}function If(e,n){function t(i,c=Ft){let o,h=tt.getTransfer(c);if(i===yt)return e.UNSIGNED_BYTE;if(i===Tr)return e.UNSIGNED_SHORT_4_4_4_4;if(i===xr)return e.UNSIGNED_SHORT_5_5_5_1;if(i===Xa)return e.UNSIGNED_INT_5_9_9_9_REV;if(i===Ka)return e.BYTE;if(i===Ya)return e.SHORT;if(i===pn)return e.UNSIGNED_SHORT;if(i===pr)return e.INT;if(i===Jt)return e.UNSIGNED_INT;if(i===Dt)return e.FLOAT;if(i===_n)return e.HALF_FLOAT;if(i===qa)return e.ALPHA;if(i===$a)return e.RGB;if(i===Tt)return e.RGBA;if(i===Qn)return e.DEPTH_COMPONENT;if(i===un)return e.DEPTH_STENCIL;if(i===Za)return e.RED;if(i===Ar)return e.RED_INTEGER;if(i===Qa)return e.RG;if(i===Rr)return e.RG_INTEGER;if(i===Cr)return e.RGBA_INTEGER;if(i===Tn||i===xn||i===An||i===Rn)if(h===Ye)if(o=n.get("WEBGL_compressed_texture_s3tc_srgb"),o!==null){if(i===Tn)return o.COMPRESSED_SRGB_S3TC_DXT1_EXT;if(i===xn)return o.COMPRESSED_SRGB_ALPHA_S3TC_DXT1_EXT;if(i===An)return o.COMPRESSED_SRGB_ALPHA_S3TC_DXT3_EXT;if(i===Rn)return o.COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT}else return null;else if(o=n.get("WEBGL_compressed_texture_s3tc"),o!==null){if(i===Tn)return o.COMPRESSED_RGB_S3TC_DXT1_EXT;if(i===xn)return o.COMPRESSED_RGBA_S3TC_DXT1_EXT;if(i===An)return o.COMPRESSED_RGBA_S3TC_DXT3_EXT;if(i===Rn)return o.COMPRESSED_RGBA_S3TC_DXT5_EXT}else return null;if(i===pi||i===hi||i===mi||i===_i)if(o=n.get("WEBGL_compressed_texture_pvrtc"),o!==null){if(i===pi)return o.COMPRESSED_RGB_PVRTC_4BPPV1_IMG;if(i===hi)return o.COMPRESSED_RGB_PVRTC_2BPPV1_IMG;if(i===mi)return o.COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;if(i===_i)return o.COMPRESSED_RGBA_PVRTC_2BPPV1_IMG}else return null;if(i===vi||i===gi||i===Si)if(o=n.get("WEBGL_compressed_texture_etc"),o!==null){if(i===vi||i===gi)return h===Ye?o.COMPRESSED_SRGB8_ETC2:o.COMPRESSED_RGB8_ETC2;if(i===Si)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ETC2_EAC:o.COMPRESSED_RGBA8_ETC2_EAC}else return null;if(i===Ei||i===Mi||i===Ti||i===xi||i===Ai||i===Ri||i===Ci||i===bi||i===Pi||i===Li||i===Ui||i===Di||i===wi||i===Ii)if(o=n.get("WEBGL_compressed_texture_astc"),o!==null){if(i===Ei)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_4x4_KHR:o.COMPRESSED_RGBA_ASTC_4x4_KHR;if(i===Mi)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_5x4_KHR:o.COMPRESSED_RGBA_ASTC_5x4_KHR;if(i===Ti)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_5x5_KHR:o.COMPRESSED_RGBA_ASTC_5x5_KHR;if(i===xi)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_6x5_KHR:o.COMPRESSED_RGBA_ASTC_6x5_KHR;if(i===Ai)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_6x6_KHR:o.COMPRESSED_RGBA_ASTC_6x6_KHR;if(i===Ri)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_8x5_KHR:o.COMPRESSED_RGBA_ASTC_8x5_KHR;if(i===Ci)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_8x6_KHR:o.COMPRESSED_RGBA_ASTC_8x6_KHR;if(i===bi)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_8x8_KHR:o.COMPRESSED_RGBA_ASTC_8x8_KHR;if(i===Pi)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_10x5_KHR:o.COMPRESSED_RGBA_ASTC_10x5_KHR;if(i===Li)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_10x6_KHR:o.COMPRESSED_RGBA_ASTC_10x6_KHR;if(i===Ui)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_10x8_KHR:o.COMPRESSED_RGBA_ASTC_10x8_KHR;if(i===Di)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_10x10_KHR:o.COMPRESSED_RGBA_ASTC_10x10_KHR;if(i===wi)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_12x10_KHR:o.COMPRESSED_RGBA_ASTC_12x10_KHR;if(i===Ii)return h===Ye?o.COMPRESSED_SRGB8_ALPHA8_ASTC_12x12_KHR:o.COMPRESSED_RGBA_ASTC_12x12_KHR}else return null;if(i===Cn||i===yi||i===Ni)if(o=n.get("EXT_texture_compression_bptc"),o!==null){if(i===Cn)return h===Ye?o.COMPRESSED_SRGB_ALPHA_BPTC_UNORM_EXT:o.COMPRESSED_RGBA_BPTC_UNORM_EXT;if(i===yi)return o.COMPRESSED_RGB_BPTC_SIGNED_FLOAT_EXT;if(i===Ni)return o.COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT_EXT}else return null;if(i===Ja||i===Oi||i===Fi||i===Bi)if(o=n.get("EXT_texture_compression_rgtc"),o!==null){if(i===Cn)return o.COMPRESSED_RED_RGTC1_EXT;if(i===Oi)return o.COMPRESSED_SIGNED_RED_RGTC1_EXT;if(i===Fi)return o.COMPRESSED_RED_GREEN_RGTC2_EXT;if(i===Bi)return o.COMPRESSED_SIGNED_RED_GREEN_RGTC2_EXT}else return null;return i===jt?e.UNSIGNED_INT_24_8:e[i]!==void 0?e[i]:null}return{convert:t}}var yf=`
void main() {

	gl_Position = vec4( position, 1.0 );

}`,Nf=`
uniform sampler2DArray depthColor;
uniform float depthWidth;
uniform float depthHeight;

void main() {

	vec2 coord = vec2( gl_FragCoord.x / depthWidth, gl_FragCoord.y / depthHeight );

	if ( coord.x >= 1.0 ) {

		gl_FragDepth = texture( depthColor, vec3( coord.x - 1.0, coord.y, 1 ) ).r;

	} else {

		gl_FragDepth = texture( depthColor, vec3( coord.x, coord.y, 0 ) ).r;

	}

}`,$n=class{constructor(){this.texture=null,this.mesh=null,this.depthNear=0,this.depthFar=0}init(n,t,i){if(this.texture===null){let c=new gr,o=n.properties.get(c);o.__webglTexture=t.texture,(t.depthNear!==i.depthNear||t.depthFar!==i.depthFar)&&(this.depthNear=t.depthNear,this.depthFar=t.depthFar),this.texture=c}}getMesh(n){if(this.texture!==null&&this.mesh===null){let t=n.cameras[0].viewport,i=new It({vertexShader:yf,fragmentShader:Nf,uniforms:{depthColor:{value:this.texture},depthWidth:{value:t.z},depthHeight:{value:t.w}}});this.mesh=new xt(new dr(20,20),i)}return this.mesh}reset(){this.texture=null,this.mesh=null}getDepthTexture(){return this.texture}},Zn=class extends ja{constructor(n,t){super();let i=this,c=null,o=1,h=null,d="local-floor",C=1,M=null,D=null,T=null,g=null,A=null,N=null,L=new $n,l=t.getContextAttributes(),r=null,U=null,x=[],_=[],H=new dt,P=null,y=new sn;y.viewport=new ft;let G=new sn;G.viewport=new ft;let p=[y,G],f=new eo,R=null,Y=null;this.cameraAutoUpdate=!0,this.enabled=!1,this.isPresenting=!1,this.getController=function(k){let j=x[k];return j===void 0&&(j=new bn,x[k]=j),j.getTargetRaySpace()},this.getControllerGrip=function(k){let j=x[k];return j===void 0&&(j=new bn,x[k]=j),j.getGripSpace()},this.getHand=function(k){let j=x[k];return j===void 0&&(j=new bn,x[k]=j),j.getHandSpace()};function V(k){let j=_.indexOf(k.inputSource);if(j===-1)return;let _e=x[j];_e!==void 0&&(_e.update(k.inputSource,k.frame,M||h),_e.dispatchEvent({type:k.type,data:k.inputSource}))}function K(){c.removeEventListener("select",V),c.removeEventListener("selectstart",V),c.removeEventListener("selectend",V),c.removeEventListener("squeeze",V),c.removeEventListener("squeezestart",V),c.removeEventListener("squeezeend",V),c.removeEventListener("end",K),c.removeEventListener("inputsourceschange",J);for(let k=0;k<x.length;k++){let j=_[k];j!==null&&(_[k]=null,x[k].disconnect(j))}R=null,Y=null,L.reset(),n.setRenderTarget(r),A=null,g=null,T=null,c=null,U=null,je.stop(),i.isPresenting=!1,n.setPixelRatio(P),n.setSize(H.width,H.height,!1),i.dispatchEvent({type:"sessionend"})}this.setFramebufferScaleFactor=function(k){o=k,i.isPresenting===!0&&console.warn("THREE.WebXRManager: Cannot change framebuffer scale while presenting.")},this.setReferenceSpaceType=function(k){d=k,i.isPresenting===!0&&console.warn("THREE.WebXRManager: Cannot change reference space type while presenting.")},this.getReferenceSpace=function(){return M||h},this.setReferenceSpace=function(k){M=k},this.getBaseLayer=function(){return g!==null?g:A},this.getBinding=function(){return T},this.getFrame=function(){return N},this.getSession=function(){return c},this.setSession=async function(k){if(c=k,c!==null){if(r=n.getRenderTarget(),c.addEventListener("select",V),c.addEventListener("selectstart",V),c.addEventListener("selectend",V),c.addEventListener("squeeze",V),c.addEventListener("squeezestart",V),c.addEventListener("squeezeend",V),c.addEventListener("end",K),c.addEventListener("inputsourceschange",J),l.xrCompatible!==!0&&await t.makeXRCompatible(),P=n.getPixelRatio(),n.getSize(H),typeof XRWebGLBinding<"u"&&"createProjectionLayer"in XRWebGLBinding.prototype){let _e=null,oe=null,ve=null;l.depth&&(ve=l.stencil?t.DEPTH24_STENCIL8:t.DEPTH_COMPONENT24,_e=l.stencil?un:Qn,oe=l.stencil?jt:Jt);let Fe={colorFormat:t.RGBA8,depthFormat:ve,scaleFactor:o};T=new XRWebGLBinding(c,t),g=T.createProjectionLayer(Fe),c.updateRenderState({layers:[g]}),n.setPixelRatio(1),n.setSize(g.textureWidth,g.textureHeight,!1),U=new zt(g.textureWidth,g.textureHeight,{format:Tt,type:yt,depthTexture:new vr(g.textureWidth,g.textureHeight,oe,void 0,void 0,void 0,void 0,void 0,void 0,_e),stencilBuffer:l.stencil,colorSpace:n.outputColorSpace,samples:l.antialias?4:0,resolveDepthBuffer:g.ignoreDepthValues===!1,resolveStencilBuffer:g.ignoreDepthValues===!1})}else{let _e={antialias:l.antialias,alpha:!0,depth:l.depth,stencil:l.stencil,framebufferScaleFactor:o};A=new XRWebGLLayer(c,t,_e),c.updateRenderState({baseLayer:A}),n.setPixelRatio(1),n.setSize(A.framebufferWidth,A.framebufferHeight,!1),U=new zt(A.framebufferWidth,A.framebufferHeight,{format:Tt,type:yt,colorSpace:n.outputColorSpace,stencilBuffer:l.stencil,resolveDepthBuffer:A.ignoreDepthValues===!1,resolveStencilBuffer:A.ignoreDepthValues===!1})}U.isXRRenderTarget=!0,this.setFoveation(C),M=null,h=await c.requestReferenceSpace(d),je.setContext(c),je.start(),i.isPresenting=!0,i.dispatchEvent({type:"sessionstart"})}},this.getEnvironmentBlendMode=function(){if(c!==null)return c.environmentBlendMode},this.getDepthTexture=function(){return L.getDepthTexture()};function J(k){for(let j=0;j<k.removed.length;j++){let _e=k.removed[j],oe=_.indexOf(_e);oe>=0&&(_[oe]=null,x[oe].disconnect(_e))}for(let j=0;j<k.added.length;j++){let _e=k.added[j],oe=_.indexOf(_e);if(oe===-1){for(let Fe=0;Fe<x.length;Fe++)if(Fe>=_.length){_.push(_e),oe=Fe;break}else if(_[Fe]===null){_[Fe]=_e,oe=Fe;break}if(oe===-1)break}let ve=x[oe];ve&&ve.connect(_e)}}let W=new We,ee=new We;function F(k,j,_e){W.setFromMatrixPosition(j.matrixWorld),ee.setFromMatrixPosition(_e.matrixWorld);let oe=W.distanceTo(ee),ve=j.projectionMatrix.elements,Fe=_e.projectionMatrix.elements,Re=ve[14]/(ve[10]-1),Ze=ve[14]/(ve[10]+1),Qe=(ve[9]+1)/ve[5],Be=(ve[9]-1)/ve[5],m=(ve[8]-1)/ve[0],ot=(Fe[8]+1)/Fe[0],Ge=Re*m,Xe=Re*ot,pe=oe/(-m+ot),ye=pe*-m;if(j.matrixWorld.decompose(k.position,k.quaternion,k.scale),k.translateX(ye),k.translateZ(pe),k.matrixWorld.compose(k.position,k.quaternion,k.scale),k.matrixWorldInverse.copy(k.matrixWorld).invert(),ve[10]===-1)k.projectionMatrix.copy(j.projectionMatrix),k.projectionMatrixInverse.copy(j.projectionMatrixInverse);else{let Ee=Re+pe,Ue=Ze+pe,nt=Ge-ye,u=Xe+(oe-ye),a=Qe*Ze/Ue*Ee,b=Be*Ze/Ue*Ee;k.projectionMatrix.makePerspective(nt,u,a,b,Ee,Ue),k.projectionMatrixInverse.copy(k.projectionMatrix).invert()}}function Se(k,j){j===null?k.matrixWorld.copy(k.matrix):k.matrixWorld.multiplyMatrices(j.matrixWorld,k.matrix),k.matrixWorldInverse.copy(k.matrixWorld).invert()}this.updateCamera=function(k){if(c===null)return;let j=k.near,_e=k.far;L.texture!==null&&(L.depthNear>0&&(j=L.depthNear),L.depthFar>0&&(_e=L.depthFar)),f.near=G.near=y.near=j,f.far=G.far=y.far=_e,(R!==f.near||Y!==f.far)&&(c.updateRenderState({depthNear:f.near,depthFar:f.far}),R=f.near,Y=f.far),y.layers.mask=k.layers.mask|2,G.layers.mask=k.layers.mask|4,f.layers.mask=y.layers.mask|G.layers.mask;let oe=k.parent,ve=f.cameras;Se(f,oe);for(let Fe=0;Fe<ve.length;Fe++)Se(ve[Fe],oe);ve.length===2?F(f,y,G):f.projectionMatrix.copy(y.projectionMatrix),Ae(k,f,oe)};function Ae(k,j,_e){_e===null?k.matrix.copy(j.matrixWorld):(k.matrix.copy(_e.matrixWorld),k.matrix.invert(),k.matrix.multiply(j.matrixWorld)),k.matrix.decompose(k.position,k.quaternion,k.scale),k.updateMatrixWorld(!0),k.projectionMatrix.copy(j.projectionMatrix),k.projectionMatrixInverse.copy(j.projectionMatrixInverse),k.isPerspectiveCamera&&(k.fov=to*2*Math.atan(1/k.projectionMatrix.elements[5]),k.zoom=1)}this.getCamera=function(){return f},this.getFoveation=function(){if(!(g===null&&A===null))return C},this.setFoveation=function(k){C=k,g!==null&&(g.fixedFoveation=k),A!==null&&A.fixedFoveation!==void 0&&(A.fixedFoveation=k)},this.hasDepthSensing=function(){return L.texture!==null},this.getDepthSensingMesh=function(){return L.getMesh(f)};let we=null;function He(k,j){if(D=j.getViewerPose(M||h),N=j,D!==null){let _e=D.views;A!==null&&(n.setRenderTargetFramebuffer(U,A.framebuffer),n.setRenderTarget(U));let oe=!1;_e.length!==f.cameras.length&&(f.cameras.length=0,oe=!0);for(let Re=0;Re<_e.length;Re++){let Ze=_e[Re],Qe=null;if(A!==null)Qe=A.getViewport(Ze);else{let m=T.getViewSubImage(g,Ze);Qe=m.viewport,Re===0&&(n.setRenderTargetTextures(U,m.colorTexture,m.depthStencilTexture),n.setRenderTarget(U))}let Be=p[Re];Be===void 0&&(Be=new sn,Be.layers.enable(Re),Be.viewport=new ft,p[Re]=Be),Be.matrix.fromArray(Ze.transform.matrix),Be.matrix.decompose(Be.position,Be.quaternion,Be.scale),Be.projectionMatrix.fromArray(Ze.projectionMatrix),Be.projectionMatrixInverse.copy(Be.projectionMatrix).invert(),Be.viewport.set(Qe.x,Qe.y,Qe.width,Qe.height),Re===0&&(f.matrix.copy(Be.matrix),f.matrix.decompose(f.position,f.quaternion,f.scale)),oe===!0&&f.cameras.push(Be)}let ve=c.enabledFeatures;if(ve&&ve.includes("depth-sensing")&&c.depthUsage=="gpu-optimized"&&T){let Re=T.getDepthInformation(_e[0]);Re&&Re.isValid&&Re.texture&&L.init(n,Re,c.renderState)}}for(let _e=0;_e<x.length;_e++){let oe=_[_e],ve=x[_e];oe!==null&&ve!==void 0&&ve.update(oe,j,M||h)}we&&we(k,j),j.detectedPlanes&&i.dispatchEvent({type:"planesdetected",data:j}),N=null}let je=new br;je.setAnimationLoop(He),this.setAnimationLoop=function(k){we=k},this.dispose=function(){}}},Pt=new fr,Of=new Vt;function Ff(e,n){function t(l,r){l.matrixAutoUpdate===!0&&l.updateMatrix(),r.value.copy(l.matrix)}function i(l,r){r.color.getRGB(l.fogColor.value,ur(e)),r.isFog?(l.fogNear.value=r.near,l.fogFar.value=r.far):r.isFogExp2&&(l.fogDensity.value=r.density)}function c(l,r,U,x,_){r.isMeshBasicMaterial||r.isMeshLambertMaterial?o(l,r):r.isMeshToonMaterial?(o(l,r),T(l,r)):r.isMeshPhongMaterial?(o(l,r),D(l,r)):r.isMeshStandardMaterial?(o(l,r),g(l,r),r.isMeshPhysicalMaterial&&A(l,r,_)):r.isMeshMatcapMaterial?(o(l,r),N(l,r)):r.isMeshDepthMaterial?o(l,r):r.isMeshDistanceMaterial?(o(l,r),L(l,r)):r.isMeshNormalMaterial?o(l,r):r.isLineBasicMaterial?(h(l,r),r.isLineDashedMaterial&&d(l,r)):r.isPointsMaterial?C(l,r,U,x):r.isSpriteMaterial?M(l,r):r.isShadowMaterial?(l.color.value.copy(r.color),l.opacity.value=r.opacity):r.isShaderMaterial&&(r.uniformsNeedUpdate=!1)}function o(l,r){l.opacity.value=r.opacity,r.color&&l.diffuse.value.copy(r.color),r.emissive&&l.emissive.value.copy(r.emissive).multiplyScalar(r.emissiveIntensity),r.map&&(l.map.value=r.map,t(r.map,l.mapTransform)),r.alphaMap&&(l.alphaMap.value=r.alphaMap,t(r.alphaMap,l.alphaMapTransform)),r.bumpMap&&(l.bumpMap.value=r.bumpMap,t(r.bumpMap,l.bumpMapTransform),l.bumpScale.value=r.bumpScale,r.side===mt&&(l.bumpScale.value*=-1)),r.normalMap&&(l.normalMap.value=r.normalMap,t(r.normalMap,l.normalMapTransform),l.normalScale.value.copy(r.normalScale),r.side===mt&&l.normalScale.value.negate()),r.displacementMap&&(l.displacementMap.value=r.displacementMap,t(r.displacementMap,l.displacementMapTransform),l.displacementScale.value=r.displacementScale,l.displacementBias.value=r.displacementBias),r.emissiveMap&&(l.emissiveMap.value=r.emissiveMap,t(r.emissiveMap,l.emissiveMapTransform)),r.specularMap&&(l.specularMap.value=r.specularMap,t(r.specularMap,l.specularMapTransform)),r.alphaTest>0&&(l.alphaTest.value=r.alphaTest);let U=n.get(r),x=U.envMap,_=U.envMapRotation;x&&(l.envMap.value=x,Pt.copy(_),Pt.x*=-1,Pt.y*=-1,Pt.z*=-1,x.isCubeTexture&&x.isRenderTargetTexture===!1&&(Pt.y*=-1,Pt.z*=-1),l.envMapRotation.value.setFromMatrix4(Of.makeRotationFromEuler(Pt)),l.flipEnvMap.value=x.isCubeTexture&&x.isRenderTargetTexture===!1?-1:1,l.reflectivity.value=r.reflectivity,l.ior.value=r.ior,l.refractionRatio.value=r.refractionRatio),r.lightMap&&(l.lightMap.value=r.lightMap,l.lightMapIntensity.value=r.lightMapIntensity,t(r.lightMap,l.lightMapTransform)),r.aoMap&&(l.aoMap.value=r.aoMap,l.aoMapIntensity.value=r.aoMapIntensity,t(r.aoMap,l.aoMapTransform))}function h(l,r){l.diffuse.value.copy(r.color),l.opacity.value=r.opacity,r.map&&(l.map.value=r.map,t(r.map,l.mapTransform))}function d(l,r){l.dashSize.value=r.dashSize,l.totalSize.value=r.dashSize+r.gapSize,l.scale.value=r.scale}function C(l,r,U,x){l.diffuse.value.copy(r.color),l.opacity.value=r.opacity,l.size.value=r.size*U,l.scale.value=x*.5,r.map&&(l.map.value=r.map,t(r.map,l.uvTransform)),r.alphaMap&&(l.alphaMap.value=r.alphaMap,t(r.alphaMap,l.alphaMapTransform)),r.alphaTest>0&&(l.alphaTest.value=r.alphaTest)}function M(l,r){l.diffuse.value.copy(r.color),l.opacity.value=r.opacity,l.rotation.value=r.rotation,r.map&&(l.map.value=r.map,t(r.map,l.mapTransform)),r.alphaMap&&(l.alphaMap.value=r.alphaMap,t(r.alphaMap,l.alphaMapTransform)),r.alphaTest>0&&(l.alphaTest.value=r.alphaTest)}function D(l,r){l.specular.value.copy(r.specular),l.shininess.value=Math.max(r.shininess,1e-4)}function T(l,r){r.gradientMap&&(l.gradientMap.value=r.gradientMap)}function g(l,r){l.metalness.value=r.metalness,r.metalnessMap&&(l.metalnessMap.value=r.metalnessMap,t(r.metalnessMap,l.metalnessMapTransform)),l.roughness.value=r.roughness,r.roughnessMap&&(l.roughnessMap.value=r.roughnessMap,t(r.roughnessMap,l.roughnessMapTransform)),r.envMap&&(l.envMapIntensity.value=r.envMapIntensity)}function A(l,r,U){l.ior.value=r.ior,r.sheen>0&&(l.sheenColor.value.copy(r.sheenColor).multiplyScalar(r.sheen),l.sheenRoughness.value=r.sheenRoughness,r.sheenColorMap&&(l.sheenColorMap.value=r.sheenColorMap,t(r.sheenColorMap,l.sheenColorMapTransform)),r.sheenRoughnessMap&&(l.sheenRoughnessMap.value=r.sheenRoughnessMap,t(r.sheenRoughnessMap,l.sheenRoughnessMapTransform))),r.clearcoat>0&&(l.clearcoat.value=r.clearcoat,l.clearcoatRoughness.value=r.clearcoatRoughness,r.clearcoatMap&&(l.clearcoatMap.value=r.clearcoatMap,t(r.clearcoatMap,l.clearcoatMapTransform)),r.clearcoatRoughnessMap&&(l.clearcoatRoughnessMap.value=r.clearcoatRoughnessMap,t(r.clearcoatRoughnessMap,l.clearcoatRoughnessMapTransform)),r.clearcoatNormalMap&&(l.clearcoatNormalMap.value=r.clearcoatNormalMap,t(r.clearcoatNormalMap,l.clearcoatNormalMapTransform),l.clearcoatNormalScale.value.copy(r.clearcoatNormalScale),r.side===mt&&l.clearcoatNormalScale.value.negate())),r.dispersion>0&&(l.dispersion.value=r.dispersion),r.iridescence>0&&(l.iridescence.value=r.iridescence,l.iridescenceIOR.value=r.iridescenceIOR,l.iridescenceThicknessMinimum.value=r.iridescenceThicknessRange[0],l.iridescenceThicknessMaximum.value=r.iridescenceThicknessRange[1],r.iridescenceMap&&(l.iridescenceMap.value=r.iridescenceMap,t(r.iridescenceMap,l.iridescenceMapTransform)),r.iridescenceThicknessMap&&(l.iridescenceThicknessMap.value=r.iridescenceThicknessMap,t(r.iridescenceThicknessMap,l.iridescenceThicknessMapTransform))),r.transmission>0&&(l.transmission.value=r.transmission,l.transmissionSamplerMap.value=U.texture,l.transmissionSamplerSize.value.set(U.width,U.height),r.transmissionMap&&(l.transmissionMap.value=r.transmissionMap,t(r.transmissionMap,l.transmissionMapTransform)),l.thickness.value=r.thickness,r.thicknessMap&&(l.thicknessMap.value=r.thicknessMap,t(r.thicknessMap,l.thicknessMapTransform)),l.attenuationDistance.value=r.attenuationDistance,l.attenuationColor.value.copy(r.attenuationColor)),r.anisotropy>0&&(l.anisotropyVector.value.set(r.anisotropy*Math.cos(r.anisotropyRotation),r.anisotropy*Math.sin(r.anisotropyRotation)),r.anisotropyMap&&(l.anisotropyMap.value=r.anisotropyMap,t(r.anisotropyMap,l.anisotropyMapTransform))),l.specularIntensity.value=r.specularIntensity,l.specularColor.value.copy(r.specularColor),r.specularColorMap&&(l.specularColorMap.value=r.specularColorMap,t(r.specularColorMap,l.specularColorMapTransform)),r.specularIntensityMap&&(l.specularIntensityMap.value=r.specularIntensityMap,t(r.specularIntensityMap,l.specularIntensityMapTransform))}function N(l,r){r.matcap&&(l.matcap.value=r.matcap)}function L(l,r){let U=n.get(r).light;l.referencePosition.value.setFromMatrixPosition(U.matrixWorld),l.nearDistance.value=U.shadow.camera.near,l.farDistance.value=U.shadow.camera.far}return{refreshFogUniforms:i,refreshMaterialUniforms:c}}function Bf(e,n,t,i){let c={},o={},h=[],d=e.getParameter(e.MAX_UNIFORM_BUFFER_BINDINGS);function C(U,x){let _=x.program;i.uniformBlockBinding(U,_)}function M(U,x){let _=c[U.id];_===void 0&&(N(U),_=D(U),c[U.id]=_,U.addEventListener("dispose",l));let H=x.program;i.updateUBOMapping(U,H);let P=n.render.frame;o[U.id]!==P&&(g(U),o[U.id]=P)}function D(U){let x=T();U.__bindingPointIndex=x;let _=e.createBuffer(),H=U.__size,P=U.usage;return e.bindBuffer(e.UNIFORM_BUFFER,_),e.bufferData(e.UNIFORM_BUFFER,H,P),e.bindBuffer(e.UNIFORM_BUFFER,null),e.bindBufferBase(e.UNIFORM_BUFFER,x,_),_}function T(){for(let U=0;U<d;U++)if(h.indexOf(U)===-1)return h.push(U),U;return console.error("THREE.WebGLRenderer: Maximum number of simultaneously usable uniforms groups reached."),0}function g(U){let x=c[U.id],_=U.uniforms,H=U.__cache;e.bindBuffer(e.UNIFORM_BUFFER,x);for(let P=0,y=_.length;P<y;P++){let G=Array.isArray(_[P])?_[P]:[_[P]];for(let p=0,f=G.length;p<f;p++){let R=G[p];if(A(R,P,p,H)===!0){let Y=R.__offset,V=Array.isArray(R.value)?R.value:[R.value],K=0;for(let J=0;J<V.length;J++){let W=V[J],ee=L(W);typeof W=="number"||typeof W=="boolean"?(R.__data[0]=W,e.bufferSubData(e.UNIFORM_BUFFER,Y+K,R.__data)):W.isMatrix3?(R.__data[0]=W.elements[0],R.__data[1]=W.elements[1],R.__data[2]=W.elements[2],R.__data[3]=0,R.__data[4]=W.elements[3],R.__data[5]=W.elements[4],R.__data[6]=W.elements[5],R.__data[7]=0,R.__data[8]=W.elements[6],R.__data[9]=W.elements[7],R.__data[10]=W.elements[8],R.__data[11]=0):(W.toArray(R.__data,K),K+=ee.storage/Float32Array.BYTES_PER_ELEMENT)}e.bufferSubData(e.UNIFORM_BUFFER,Y,R.__data)}}}e.bindBuffer(e.UNIFORM_BUFFER,null)}function A(U,x,_,H){let P=U.value,y=x+"_"+_;if(H[y]===void 0)return typeof P=="number"||typeof P=="boolean"?H[y]=P:H[y]=P.clone(),!0;{let G=H[y];if(typeof P=="number"||typeof P=="boolean"){if(G!==P)return H[y]=P,!0}else if(G.equals(P)===!1)return G.copy(P),!0}return!1}function N(U){let x=U.uniforms,_=0,H=16;for(let y=0,G=x.length;y<G;y++){let p=Array.isArray(x[y])?x[y]:[x[y]];for(let f=0,R=p.length;f<R;f++){let Y=p[f],V=Array.isArray(Y.value)?Y.value:[Y.value];for(let K=0,J=V.length;K<J;K++){let W=V[K],ee=L(W),F=_%H,Se=F%ee.boundary,Ae=F+Se;_+=Se,Ae!==0&&H-Ae<ee.storage&&(_+=H-Ae),Y.__data=new Float32Array(ee.storage/Float32Array.BYTES_PER_ELEMENT),Y.__offset=_,_+=ee.storage}}}let P=_%H;return P>0&&(_+=H-P),U.__size=_,U.__cache={},this}function L(U){let x={boundary:0,storage:0};return typeof U=="number"||typeof U=="boolean"?(x.boundary=4,x.storage=4):U.isVector2?(x.boundary=8,x.storage=8):U.isVector3||U.isColor?(x.boundary=16,x.storage=12):U.isVector4?(x.boundary=16,x.storage=16):U.isMatrix3?(x.boundary=48,x.storage=48):U.isMatrix4?(x.boundary=64,x.storage=64):U.isTexture?console.warn("THREE.WebGLRenderer: Texture samplers can not be part of an uniforms group."):console.warn("THREE.WebGLRenderer: Unsupported uniform value type.",U),x}function l(U){let x=U.target;x.removeEventListener("dispose",l);let _=h.indexOf(x.__bindingPointIndex);h.splice(_,1),e.deleteBuffer(c[x.id]),delete c[x.id],delete o[x.id]}function r(){for(let U in c)e.deleteBuffer(c[U]);h=[],c={},o={}}return{bind:C,update:M,dispose:r}}var cr=class{constructor(n={}){let{canvas:t=no(),context:i=null,depth:c=!0,stencil:o=!1,alpha:h=!1,antialias:d=!1,premultipliedAlpha:C=!0,preserveDrawingBuffer:M=!1,powerPreference:D="default",failIfMajorPerformanceCaveat:T=!1,reverseDepthBuffer:g=!1}=n;this.isWebGLRenderer=!0;let A;if(i!==null){if(typeof WebGLRenderingContext<"u"&&i instanceof WebGLRenderingContext)throw new Error("THREE.WebGLRenderer: WebGL 1 is not supported since r163.");A=i.getContextAttributes().alpha}else A=h;let N=new Uint32Array(4),L=new Int32Array(4),l=null,r=null,U=[],x=[];this.domElement=t,this.debug={checkShaderErrors:!0,onShaderError:null},this.autoClear=!0,this.autoClearColor=!0,this.autoClearDepth=!0,this.autoClearStencil=!0,this.sortObjects=!0,this.clippingPlanes=[],this.localClippingEnabled=!1,this.toneMapping=At,this.toneMappingExposure=1,this.transmissionResolutionScale=1;let _=this,H=!1;this._outputColorSpace=io;let P=0,y=0,G=null,p=-1,f=null,R=new ft,Y=new ft,V=null,K=new $e(0),J=0,W=t.width,ee=t.height,F=1,Se=null,Ae=null,we=new ft(0,0,W,ee),He=new ft(0,0,W,ee),je=!1,k=new Mr,j=!1,_e=!1,oe=new Vt,ve=new Vt,Fe=new We,Re=new ft,Ze={background:null,fog:null,environment:null,overrideMaterial:null,isScene:!0},Qe=!1;function Be(){return G===null?F:1}let m=i;function ot(s,S){return t.getContext(s,S)}try{let s={alpha:!0,depth:c,stencil:o,antialias:d,premultipliedAlpha:C,preserveDrawingBuffer:M,powerPreference:D,failIfMajorPerformanceCaveat:T};if("setAttribute"in t&&t.setAttribute("data-engine",`three.js r${ro}`),t.addEventListener("webglcontextlost",le,!1),t.addEventListener("webglcontextrestored",Z,!1),t.addEventListener("webglcontextcreationerror",z,!1),m===null){let S="webgl2";if(m=ot(S,s),m===null)throw ot(S)?new Error("Error creating WebGL context with your selected attributes."):new Error("Error creating WebGL context.")}}catch(s){throw console.error("THREE.WebGLRenderer: "+s.message),s}let Ge,Xe,pe,ye,Ee,Ue,nt,u,a,b,B,X,O,he,ie,ue,me,q,se,xe,Te,te,Pe,v;function re(){Ge=new tl(m),Ge.init(),te=new If(m,Ge),Xe=new qc(m,Ge,n,te),pe=new Df(m,Ge),Xe.reverseDepthBuffer&&g&&pe.buffers.depth.setReversed(!0),ye=new rl(m),Ee=new gf,Ue=new wf(m,Ge,pe,Ee,Xe,te,ye),nt=new Zc(_),u=new el(_),a=new lo(m),Pe=new Kc(m,a),b=new nl(m,a,ye,Pe),B=new ol(m,b,a,ye),se=new al(m,Xe,Ue),ue=new $c(Ee),X=new vf(_,nt,u,Ge,Xe,Pe,ue),O=new Ff(_,Ee),he=new Ef,ie=new Cf(Ge),q=new Xc(_,nt,u,pe,B,A,C),me=new Lf(_,B,Xe),v=new Bf(m,ye,Xe,pe),xe=new Yc(m,Ge,ye),Te=new il(m,Ge,ye),ye.programs=X.programs,_.capabilities=Xe,_.extensions=Ge,_.properties=Ee,_.renderLists=he,_.shadowMap=me,_.state=pe,_.info=ye}re();let $=new Zn(_,m);this.xr=$,this.getContext=function(){return m},this.getContextAttributes=function(){return m.getContextAttributes()},this.forceContextLoss=function(){let s=Ge.get("WEBGL_lose_context");s&&s.loseContext()},this.forceContextRestore=function(){let s=Ge.get("WEBGL_lose_context");s&&s.restoreContext()},this.getPixelRatio=function(){return F},this.setPixelRatio=function(s){s!==void 0&&(F=s,this.setSize(W,ee,!1))},this.getSize=function(s){return s.set(W,ee)},this.setSize=function(s,S,w=!0){if($.isPresenting){console.warn("THREE.WebGLRenderer: Can't change size while VR device is presenting.");return}W=s,ee=S,t.width=Math.floor(s*F),t.height=Math.floor(S*F),w===!0&&(t.style.width=s+"px",t.style.height=S+"px"),this.setViewport(0,0,s,S)},this.getDrawingBufferSize=function(s){return s.set(W*F,ee*F).floor()},this.setDrawingBufferSize=function(s,S,w){W=s,ee=S,F=w,t.width=Math.floor(s*w),t.height=Math.floor(S*w),this.setViewport(0,0,s,S)},this.getCurrentViewport=function(s){return s.copy(R)},this.getViewport=function(s){return s.copy(we)},this.setViewport=function(s,S,w,I){s.isVector4?we.set(s.x,s.y,s.z,s.w):we.set(s,S,w,I),pe.viewport(R.copy(we).multiplyScalar(F).round())},this.getScissor=function(s){return s.copy(He)},this.setScissor=function(s,S,w,I){s.isVector4?He.set(s.x,s.y,s.z,s.w):He.set(s,S,w,I),pe.scissor(Y.copy(He).multiplyScalar(F).round())},this.getScissorTest=function(){return je},this.setScissorTest=function(s){pe.setScissorTest(je=s)},this.setOpaqueSort=function(s){Se=s},this.setTransparentSort=function(s){Ae=s},this.getClearColor=function(s){return s.copy(q.getClearColor())},this.setClearColor=function(){q.setClearColor(...arguments)},this.getClearAlpha=function(){return q.getClearAlpha()},this.setClearAlpha=function(){q.setClearAlpha(...arguments)},this.clear=function(s=!0,S=!0,w=!0){let I=0;if(s){let E=!1;if(G!==null){let Q=G.texture.format;E=Q===Cr||Q===Rr||Q===Ar}if(E){let Q=G.texture.type,ae=Q===yt||Q===Jt||Q===pn||Q===jt||Q===Tr||Q===xr,de=q.getClearColor(),ce=q.getClearAlpha(),Ce=de.r,be=de.g,ge=de.b;ae?(N[0]=Ce,N[1]=be,N[2]=ge,N[3]=ce,m.clearBufferuiv(m.COLOR,0,N)):(L[0]=Ce,L[1]=be,L[2]=ge,L[3]=ce,m.clearBufferiv(m.COLOR,0,L))}else I|=m.COLOR_BUFFER_BIT}S&&(I|=m.DEPTH_BUFFER_BIT),w&&(I|=m.STENCIL_BUFFER_BIT,this.state.buffers.stencil.setMask(4294967295)),m.clear(I)},this.clearColor=function(){this.clear(!0,!1,!1)},this.clearDepth=function(){this.clear(!1,!0,!1)},this.clearStencil=function(){this.clear(!1,!1,!0)},this.dispose=function(){t.removeEventListener("webglcontextlost",le,!1),t.removeEventListener("webglcontextrestored",Z,!1),t.removeEventListener("webglcontextcreationerror",z,!1),q.dispose(),he.dispose(),ie.dispose(),Ee.dispose(),nt.dispose(),u.dispose(),B.dispose(),Pe.dispose(),v.dispose(),X.dispose(),$.dispose(),$.removeEventListener("sessionstart",jn),$.removeEventListener("sessionend",ei),Rt.stop()};function le(s){s.preventDefault(),console.log("THREE.WebGLRenderer: Context Lost."),H=!0}function Z(){console.log("THREE.WebGLRenderer: Context Restored."),H=!1;let s=ye.autoReset,S=me.enabled,w=me.autoUpdate,I=me.needsUpdate,E=me.type;re(),ye.autoReset=s,me.enabled=S,me.autoUpdate=w,me.needsUpdate=I,me.type=E}function z(s){console.error("THREE.WebGLRenderer: A WebGL context could not be created. Reason: ",s.statusMessage)}function fe(s){let S=s.target;S.removeEventListener("dispose",fe),Le(S)}function Le(s){Ke(s),Ee.remove(s)}function Ke(s){let S=Ee.get(s).programs;S!==void 0&&(S.forEach(function(w){X.releaseProgram(w)}),s.isShaderMaterial&&X.releaseShaderCache(s))}this.renderBufferDirect=function(s,S,w,I,E,Q){S===null&&(S=Ze);let ae=E.isMesh&&E.matrixWorld.determinant()<0,de=wr(s,S,w,I,E);pe.setMaterial(I,ae);let ce=w.index,Ce=1;if(I.wireframe===!0){if(ce=b.getWireframeAttribute(w),ce===void 0)return;Ce=2}let be=w.drawRange,ge=w.attributes.position,Ie=be.start*Ce,ze=(be.start+be.count)*Ce;Q!==null&&(Ie=Math.max(Ie,Q.start*Ce),ze=Math.min(ze,(Q.start+Q.count)*Ce)),ce!==null?(Ie=Math.max(Ie,0),ze=Math.min(ze,ce.count)):ge!=null&&(Ie=Math.max(Ie,0),ze=Math.min(ze,ge.count));let Je=ze-Ie;if(Je<0||Je===1/0)return;Pe.setup(E,I,de,w,ce);let et,Ne=xe;if(ce!==null&&(et=a.get(ce),Ne=Te,Ne.setIndex(et)),E.isMesh)I.wireframe===!0?(pe.setLineWidth(I.wireframeLinewidth*Be()),Ne.setMode(m.LINES)):Ne.setMode(m.TRIANGLES);else if(E.isLine){let Me=I.linewidth;Me===void 0&&(Me=1),pe.setLineWidth(Me*Be()),E.isLineSegments?Ne.setMode(m.LINES):E.isLineLoop?Ne.setMode(m.LINE_LOOP):Ne.setMode(m.LINE_STRIP)}else E.isPoints?Ne.setMode(m.POINTS):E.isSprite&&Ne.setMode(m.TRIANGLES);if(E.isBatchedMesh)if(E._multiDrawInstances!==null)ln("THREE.WebGLRenderer: renderMultiDrawInstances has been deprecated and will be removed in r184. Append to renderMultiDraw arguments and use indirection."),Ne.renderMultiDrawInstances(E._multiDrawStarts,E._multiDrawCounts,E._multiDrawCount,E._multiDrawInstances);else if(Ge.get("WEBGL_multi_draw"))Ne.renderMultiDraw(E._multiDrawStarts,E._multiDrawCounts,E._multiDrawCount);else{let Me=E._multiDrawStarts,at=E._multiDrawCounts,Ve=E._multiDrawCount,vt=ce?a.get(ce).bytesPerElement:1,Nt=Ee.get(I).currentProgram.getUniforms();for(let ut=0;ut<Ve;ut++)Nt.setValue(m,"_gl_DrawID",ut),Ne.render(Me[ut]/vt,at[ut])}else if(E.isInstancedMesh)Ne.renderInstances(Ie,Je,E.count);else if(w.isInstancedBufferGeometry){let Me=w._maxInstanceCount!==void 0?w._maxInstanceCount:1/0,at=Math.min(w.instanceCount,Me);Ne.renderInstances(Ie,Je,at)}else Ne.render(Ie,Je)};function ke(s,S,w){s.transparent===!0&&s.side===Mt&&s.forceSinglePass===!1?(s.side=mt,s.needsUpdate=!0,tn(s,S,w),s.side=Zt,s.needsUpdate=!0,tn(s,S,w),s.side=Mt):tn(s,S,w)}this.compile=function(s,S,w=null){w===null&&(w=s),r=ie.get(w),r.init(S),x.push(r),w.traverseVisible(function(E){E.isLight&&E.layers.test(S.layers)&&(r.pushLight(E),E.castShadow&&r.pushShadow(E))}),s!==w&&s.traverseVisible(function(E){E.isLight&&E.layers.test(S.layers)&&(r.pushLight(E),E.castShadow&&r.pushShadow(E))}),r.setupLights();let I=new Set;return s.traverse(function(E){if(!(E.isMesh||E.isPoints||E.isLine||E.isSprite))return;let Q=E.material;if(Q)if(Array.isArray(Q))for(let ae=0;ae<Q.length;ae++){let de=Q[ae];ke(de,w,E),I.add(de)}else ke(Q,w,E),I.add(Q)}),r=x.pop(),I},this.compileAsync=function(s,S,w=null){let I=this.compile(s,S,w);return new Promise(E=>{function Q(){if(I.forEach(function(ae){Ee.get(ae).currentProgram.isReady()&&I.delete(ae)}),I.size===0){E(s);return}setTimeout(Q,10)}Ge.get("KHR_parallel_shader_compile")!==null?Q():setTimeout(Q,10)})};let _t=null;function St(s){_t&&_t(s)}function jn(){Rt.stop()}function ei(){Rt.start()}let Rt=new br;Rt.setAnimationLoop(St),typeof self<"u"&&Rt.setContext(self),this.setAnimationLoop=function(s){_t=s,$.setAnimationLoop(s),s===null?Rt.stop():Rt.start()},$.addEventListener("sessionstart",jn),$.addEventListener("sessionend",ei),this.render=function(s,S){if(S!==void 0&&S.isCamera!==!0){console.error("THREE.WebGLRenderer.render: camera is not an instance of THREE.Camera.");return}if(H===!0)return;if(s.matrixWorldAutoUpdate===!0&&s.updateMatrixWorld(),S.parent===null&&S.matrixWorldAutoUpdate===!0&&S.updateMatrixWorld(),$.enabled===!0&&$.isPresenting===!0&&($.cameraAutoUpdate===!0&&$.updateCamera(S),S=$.getCamera()),s.isScene===!0&&s.onBeforeRender(_,s,S,G),r=ie.get(s,x.length),r.init(S),x.push(r),ve.multiplyMatrices(S.projectionMatrix,S.matrixWorldInverse),k.setFromProjectionMatrix(ve),_e=this.localClippingEnabled,j=ue.init(this.clippingPlanes,_e),l=he.get(s,U.length),l.init(),U.push(l),$.enabled===!0&&$.isPresenting===!0){let Q=_.xr.getDepthSensingMesh();Q!==null&&Sn(Q,S,-1/0,_.sortObjects)}Sn(s,S,0,_.sortObjects),l.finish(),_.sortObjects===!0&&l.sort(Se,Ae),Qe=$.enabled===!1||$.isPresenting===!1||$.hasDepthSensing()===!1,Qe&&q.addToRenderList(l,s),this.info.render.frame++,j===!0&&ue.beginShadows();let w=r.state.shadowsArray;me.render(w,s,S),j===!0&&ue.endShadows(),this.info.autoReset===!0&&this.info.reset();let I=l.opaque,E=l.transmissive;if(r.setupLights(),S.isArrayCamera){let Q=S.cameras;if(E.length>0)for(let ae=0,de=Q.length;ae<de;ae++){let ce=Q[ae];ni(I,E,s,ce)}Qe&&q.render(s);for(let ae=0,de=Q.length;ae<de;ae++){let ce=Q[ae];ti(l,s,ce,ce.viewport)}}else E.length>0&&ni(I,E,s,S),Qe&&q.render(s),ti(l,s,S);G!==null&&y===0&&(Ue.updateMultisampleRenderTarget(G),Ue.updateRenderTargetMipmap(G)),s.isScene===!0&&s.onAfterRender(_,s,S),Pe.resetDefaultState(),p=-1,f=null,x.pop(),x.length>0?(r=x[x.length-1],j===!0&&ue.setGlobalState(_.clippingPlanes,r.state.camera)):r=null,U.pop(),U.length>0?l=U[U.length-1]:l=null};function Sn(s,S,w,I){if(s.visible===!1)return;if(s.layers.test(S.layers)){if(s.isGroup)w=s.renderOrder;else if(s.isLOD)s.autoUpdate===!0&&s.update(S);else if(s.isLight)r.pushLight(s),s.castShadow&&r.pushShadow(s);else if(s.isSprite){if(!s.frustumCulled||k.intersectsSprite(s)){I&&Re.setFromMatrixPosition(s.matrixWorld).applyMatrix4(ve);let ae=B.update(s),de=s.material;de.visible&&l.push(s,ae,de,w,Re.z,null)}}else if((s.isMesh||s.isLine||s.isPoints)&&(!s.frustumCulled||k.intersectsObject(s))){let ae=B.update(s),de=s.material;if(I&&(s.boundingSphere!==void 0?(s.boundingSphere===null&&s.computeBoundingSphere(),Re.copy(s.boundingSphere.center)):(ae.boundingSphere===null&&ae.computeBoundingSphere(),Re.copy(ae.boundingSphere.center)),Re.applyMatrix4(s.matrixWorld).applyMatrix4(ve)),Array.isArray(de)){let ce=ae.groups;for(let Ce=0,be=ce.length;Ce<be;Ce++){let ge=ce[Ce],Ie=de[ge.materialIndex];Ie&&Ie.visible&&l.push(s,ae,Ie,w,Re.z,ge)}}else de.visible&&l.push(s,ae,de,w,Re.z,null)}}let Q=s.children;for(let ae=0,de=Q.length;ae<de;ae++)Sn(Q[ae],S,w,I)}function ti(s,S,w,I){let E=s.opaque,Q=s.transmissive,ae=s.transparent;r.setupLightsView(w),j===!0&&ue.setGlobalState(_.clippingPlanes,w),I&&pe.viewport(R.copy(I)),E.length>0&&en(E,S,w),Q.length>0&&en(Q,S,w),ae.length>0&&en(ae,S,w),pe.buffers.depth.setTest(!0),pe.buffers.depth.setMask(!0),pe.buffers.color.setMask(!0),pe.setPolygonOffset(!1)}function ni(s,S,w,I){if((w.isScene===!0?w.overrideMaterial:null)!==null)return;r.state.transmissionRenderTarget[I.id]===void 0&&(r.state.transmissionRenderTarget[I.id]=new zt(1,1,{generateMipmaps:!0,type:Ge.has("EXT_color_buffer_half_float")||Ge.has("EXT_color_buffer_float")?_n:yt,minFilter:Yt,samples:4,stencilBuffer:o,resolveDepthBuffer:!1,resolveStencilBuffer:!1,colorSpace:tt.workingColorSpace}));let Q=r.state.transmissionRenderTarget[I.id],ae=I.viewport||R;Q.setSize(ae.z*_.transmissionResolutionScale,ae.w*_.transmissionResolutionScale);let de=_.getRenderTarget();_.setRenderTarget(Q),_.getClearColor(K),J=_.getClearAlpha(),J<1&&_.setClearColor(16777215,.5),_.clear(),Qe&&q.render(w);let ce=_.toneMapping;_.toneMapping=At;let Ce=I.viewport;if(I.viewport!==void 0&&(I.viewport=void 0),r.setupLightsView(I),j===!0&&ue.setGlobalState(_.clippingPlanes,I),en(s,w,I),Ue.updateMultisampleRenderTarget(Q),Ue.updateRenderTargetMipmap(Q),Ge.has("WEBGL_multisampled_render_to_texture")===!1){let be=!1;for(let ge=0,Ie=S.length;ge<Ie;ge++){let ze=S[ge],Je=ze.object,et=ze.geometry,Ne=ze.material,Me=ze.group;if(Ne.side===Mt&&Je.layers.test(I.layers)){let at=Ne.side;Ne.side=mt,Ne.needsUpdate=!0,ii(Je,w,I,et,Ne,Me),Ne.side=at,Ne.needsUpdate=!0,be=!0}}be===!0&&(Ue.updateMultisampleRenderTarget(Q),Ue.updateRenderTargetMipmap(Q))}_.setRenderTarget(de),_.setClearColor(K,J),Ce!==void 0&&(I.viewport=Ce),_.toneMapping=ce}function en(s,S,w){let I=S.isScene===!0?S.overrideMaterial:null;for(let E=0,Q=s.length;E<Q;E++){let ae=s[E],de=ae.object,ce=ae.geometry,Ce=ae.group,be=ae.material;be.allowOverride===!0&&I!==null&&(be=I),de.layers.test(w.layers)&&ii(de,S,w,ce,be,Ce)}}function ii(s,S,w,I,E,Q){s.onBeforeRender(_,S,w,I,E,Q),s.modelViewMatrix.multiplyMatrices(w.matrixWorldInverse,s.matrixWorld),s.normalMatrix.getNormalMatrix(s.modelViewMatrix),E.onBeforeRender(_,S,w,I,s,Q),E.transparent===!0&&E.side===Mt&&E.forceSinglePass===!1?(E.side=mt,E.needsUpdate=!0,_.renderBufferDirect(w,S,I,E,s,Q),E.side=Zt,E.needsUpdate=!0,_.renderBufferDirect(w,S,I,E,s,Q),E.side=Mt):_.renderBufferDirect(w,S,I,E,s,Q),s.onAfterRender(_,S,w,I,E,Q)}function tn(s,S,w){S.isScene!==!0&&(S=Ze);let I=Ee.get(s),E=r.state.lights,Q=r.state.shadowsArray,ae=E.state.version,de=X.getParameters(s,E.state,Q,S,w),ce=X.getProgramCacheKey(de),Ce=I.programs;I.environment=s.isMeshStandardMaterial?S.environment:null,I.fog=S.fog,I.envMap=(s.isMeshStandardMaterial?u:nt).get(s.envMap||I.environment),I.envMapRotation=I.environment!==null&&s.envMap===null?S.environmentRotation:s.envMapRotation,Ce===void 0&&(s.addEventListener("dispose",fe),Ce=new Map,I.programs=Ce);let be=Ce.get(ce);if(be!==void 0){if(I.currentProgram===be&&I.lightsStateVersion===ae)return ai(s,de),be}else de.uniforms=X.getUniforms(s),s.onBeforeCompile(de,_),be=X.acquireProgram(de,ce),Ce.set(ce,be),I.uniforms=de.uniforms;let ge=I.uniforms;return(!s.isShaderMaterial&&!s.isRawShaderMaterial||s.clipping===!0)&&(ge.clippingPlanes=ue.uniform),ai(s,de),I.needsLights=yr(s),I.lightsStateVersion=ae,I.needsLights&&(ge.ambientLightColor.value=E.state.ambient,ge.lightProbe.value=E.state.probe,ge.directionalLights.value=E.state.directional,ge.directionalLightShadows.value=E.state.directionalShadow,ge.spotLights.value=E.state.spot,ge.spotLightShadows.value=E.state.spotShadow,ge.rectAreaLights.value=E.state.rectArea,ge.ltc_1.value=E.state.rectAreaLTC1,ge.ltc_2.value=E.state.rectAreaLTC2,ge.pointLights.value=E.state.point,ge.pointLightShadows.value=E.state.pointShadow,ge.hemisphereLights.value=E.state.hemi,ge.directionalShadowMap.value=E.state.directionalShadowMap,ge.directionalShadowMatrix.value=E.state.directionalShadowMatrix,ge.spotShadowMap.value=E.state.spotShadowMap,ge.spotLightMatrix.value=E.state.spotLightMatrix,ge.spotLightMap.value=E.state.spotLightMap,ge.pointShadowMap.value=E.state.pointShadowMap,ge.pointShadowMatrix.value=E.state.pointShadowMatrix),I.currentProgram=be,I.uniformsList=null,be}function ri(s){if(s.uniformsList===null){let S=s.currentProgram.getUniforms();s.uniformsList=Ht.seqWithValue(S.seq,s.uniforms)}return s.uniformsList}function ai(s,S){let w=Ee.get(s);w.outputColorSpace=S.outputColorSpace,w.batching=S.batching,w.batchingColor=S.batchingColor,w.instancing=S.instancing,w.instancingColor=S.instancingColor,w.instancingMorph=S.instancingMorph,w.skinning=S.skinning,w.morphTargets=S.morphTargets,w.morphNormals=S.morphNormals,w.morphColors=S.morphColors,w.morphTargetsCount=S.morphTargetsCount,w.numClippingPlanes=S.numClippingPlanes,w.numIntersection=S.numClipIntersection,w.vertexAlphas=S.vertexAlphas,w.vertexTangents=S.vertexTangents,w.toneMapping=S.toneMapping}function wr(s,S,w,I,E){S.isScene!==!0&&(S=Ze),Ue.resetTextureUnits();let Q=S.fog,ae=I.isMeshStandardMaterial?S.environment:null,de=G===null?_.outputColorSpace:G.isXRRenderTarget===!0?G.texture.colorSpace:vn,ce=(I.isMeshStandardMaterial?u:nt).get(I.envMap||ae),Ce=I.vertexColors===!0&&!!w.attributes.color&&w.attributes.color.itemSize===4,be=!!w.attributes.tangent&&(!!I.normalMap||I.anisotropy>0),ge=!!w.morphAttributes.position,Ie=!!w.morphAttributes.normal,ze=!!w.morphAttributes.color,Je=At;I.toneMapped&&(G===null||G.isXRRenderTarget===!0)&&(Je=_.toneMapping);let et=w.morphAttributes.position||w.morphAttributes.normal||w.morphAttributes.color,Ne=et!==void 0?et.length:0,Me=Ee.get(I),at=r.state.lights;if(j===!0&&(_e===!0||s!==f)){let st=s===f&&I.id===p;ue.setState(I,s,st)}let Ve=!1;I.version===Me.__version?(Me.needsLights&&Me.lightsStateVersion!==at.state.version||Me.outputColorSpace!==de||E.isBatchedMesh&&Me.batching===!1||!E.isBatchedMesh&&Me.batching===!0||E.isBatchedMesh&&Me.batchingColor===!0&&E.colorTexture===null||E.isBatchedMesh&&Me.batchingColor===!1&&E.colorTexture!==null||E.isInstancedMesh&&Me.instancing===!1||!E.isInstancedMesh&&Me.instancing===!0||E.isSkinnedMesh&&Me.skinning===!1||!E.isSkinnedMesh&&Me.skinning===!0||E.isInstancedMesh&&Me.instancingColor===!0&&E.instanceColor===null||E.isInstancedMesh&&Me.instancingColor===!1&&E.instanceColor!==null||E.isInstancedMesh&&Me.instancingMorph===!0&&E.morphTexture===null||E.isInstancedMesh&&Me.instancingMorph===!1&&E.morphTexture!==null||Me.envMap!==ce||I.fog===!0&&Me.fog!==Q||Me.numClippingPlanes!==void 0&&(Me.numClippingPlanes!==ue.numPlanes||Me.numIntersection!==ue.numIntersection)||Me.vertexAlphas!==Ce||Me.vertexTangents!==be||Me.morphTargets!==ge||Me.morphNormals!==Ie||Me.morphColors!==ze||Me.toneMapping!==Je||Me.morphTargetsCount!==Ne)&&(Ve=!0):(Ve=!0,Me.__version=I.version);let vt=Me.currentProgram;Ve===!0&&(vt=tn(I,S,E));let Nt=!1,ut=!1,Xt=!1,qe=vt.getUniforms(),pt=Me.uniforms;if(pe.useProgram(vt.program)&&(Nt=!0,ut=!0,Xt=!0),I.id!==p&&(p=I.id,ut=!0),Nt||f!==s){pe.buffers.depth.getReversed()?(oe.copy(s.projectionMatrix),ao(oe),oo(oe),qe.setValue(m,"projectionMatrix",oe)):qe.setValue(m,"projectionMatrix",s.projectionMatrix),qe.setValue(m,"viewMatrix",s.matrixWorldInverse);let ct=qe.map.cameraPosition;ct!==void 0&&ct.setValue(m,Fe.setFromMatrixPosition(s.matrixWorld)),Xe.logarithmicDepthBuffer&&qe.setValue(m,"logDepthBufFC",2/(Math.log(s.far+1)/Math.LN2)),(I.isMeshPhongMaterial||I.isMeshToonMaterial||I.isMeshLambertMaterial||I.isMeshBasicMaterial||I.isMeshStandardMaterial||I.isShaderMaterial)&&qe.setValue(m,"isOrthographic",s.isOrthographicCamera===!0),f!==s&&(f=s,ut=!0,Xt=!0)}if(E.isSkinnedMesh){qe.setOptional(m,E,"bindMatrix"),qe.setOptional(m,E,"bindMatrixInverse");let st=E.skeleton;st&&(st.boneTexture===null&&st.computeBoneTexture(),qe.setValue(m,"boneTexture",st.boneTexture,Ue))}E.isBatchedMesh&&(qe.setOptional(m,E,"batchingTexture"),qe.setValue(m,"batchingTexture",E._matricesTexture,Ue),qe.setOptional(m,E,"batchingIdTexture"),qe.setValue(m,"batchingIdTexture",E._indirectTexture,Ue),qe.setOptional(m,E,"batchingColorTexture"),E._colorsTexture!==null&&qe.setValue(m,"batchingColorTexture",E._colorsTexture,Ue));let ht=w.morphAttributes;if((ht.position!==void 0||ht.normal!==void 0||ht.color!==void 0)&&se.update(E,w,vt),(ut||Me.receiveShadow!==E.receiveShadow)&&(Me.receiveShadow=E.receiveShadow,qe.setValue(m,"receiveShadow",E.receiveShadow)),I.isMeshGouraudMaterial&&I.envMap!==null&&(pt.envMap.value=ce,pt.flipEnvMap.value=ce.isCubeTexture&&ce.isRenderTargetTexture===!1?-1:1),I.isMeshStandardMaterial&&I.envMap===null&&S.environment!==null&&(pt.envMapIntensity.value=S.environmentIntensity),ut&&(qe.setValue(m,"toneMappingExposure",_.toneMappingExposure),Me.needsLights&&Ir(pt,Xt),Q&&I.fog===!0&&O.refreshFogUniforms(pt,Q),O.refreshMaterialUniforms(pt,I,F,ee,r.state.transmissionRenderTarget[s.id]),Ht.upload(m,ri(Me),pt,Ue)),I.isShaderMaterial&&I.uniformsNeedUpdate===!0&&(Ht.upload(m,ri(Me),pt,Ue),I.uniformsNeedUpdate=!1),I.isSpriteMaterial&&qe.setValue(m,"center",E.center),qe.setValue(m,"modelViewMatrix",E.modelViewMatrix),qe.setValue(m,"normalMatrix",E.normalMatrix),qe.setValue(m,"modelMatrix",E.matrixWorld),I.isShaderMaterial||I.isRawShaderMaterial){let st=I.uniformsGroups;for(let ct=0,En=st.length;ct<En;ct++){let Ct=st[ct];v.update(Ct,vt),v.bind(Ct,vt)}}return vt}function Ir(s,S){s.ambientLightColor.needsUpdate=S,s.lightProbe.needsUpdate=S,s.directionalLights.needsUpdate=S,s.directionalLightShadows.needsUpdate=S,s.pointLights.needsUpdate=S,s.pointLightShadows.needsUpdate=S,s.spotLights.needsUpdate=S,s.spotLightShadows.needsUpdate=S,s.rectAreaLights.needsUpdate=S,s.hemisphereLights.needsUpdate=S}function yr(s){return s.isMeshLambertMaterial||s.isMeshToonMaterial||s.isMeshPhongMaterial||s.isMeshStandardMaterial||s.isShadowMaterial||s.isShaderMaterial&&s.lights===!0}this.getActiveCubeFace=function(){return P},this.getActiveMipmapLevel=function(){return y},this.getRenderTarget=function(){return G},this.setRenderTargetTextures=function(s,S,w){let I=Ee.get(s);I.__autoAllocateDepthBuffer=s.resolveDepthBuffer===!1,I.__autoAllocateDepthBuffer===!1&&(I.__useRenderToTexture=!1),Ee.get(s.texture).__webglTexture=S,Ee.get(s.depthTexture).__webglTexture=I.__autoAllocateDepthBuffer?void 0:w,I.__hasExternalTextures=!0},this.setRenderTargetFramebuffer=function(s,S){let w=Ee.get(s);w.__webglFramebuffer=S,w.__useDefaultFramebuffer=S===void 0};let Nr=m.createFramebuffer();this.setRenderTarget=function(s,S=0,w=0){G=s,P=S,y=w;let I=!0,E=null,Q=!1,ae=!1;if(s){let ce=Ee.get(s);if(ce.__useDefaultFramebuffer!==void 0)pe.bindFramebuffer(m.FRAMEBUFFER,null),I=!1;else if(ce.__webglFramebuffer===void 0)Ue.setupRenderTarget(s);else if(ce.__hasExternalTextures)Ue.rebindTextures(s,Ee.get(s.texture).__webglTexture,Ee.get(s.depthTexture).__webglTexture);else if(s.depthBuffer){let ge=s.depthTexture;if(ce.__boundDepthTexture!==ge){if(ge!==null&&Ee.has(ge)&&(s.width!==ge.image.width||s.height!==ge.image.height))throw new Error("WebGLRenderTarget: Attached DepthTexture is initialized to the incorrect size.");Ue.setupDepthRenderbuffer(s)}}let Ce=s.texture;(Ce.isData3DTexture||Ce.isDataArrayTexture||Ce.isCompressedArrayTexture)&&(ae=!0);let be=Ee.get(s).__webglFramebuffer;s.isWebGLCubeRenderTarget?(Array.isArray(be[S])?E=be[S][w]:E=be[S],Q=!0):s.samples>0&&Ue.useMultisampledRTT(s)===!1?E=Ee.get(s).__webglMultisampledFramebuffer:Array.isArray(be)?E=be[w]:E=be,R.copy(s.viewport),Y.copy(s.scissor),V=s.scissorTest}else R.copy(we).multiplyScalar(F).floor(),Y.copy(He).multiplyScalar(F).floor(),V=je;if(w!==0&&(E=Nr),pe.bindFramebuffer(m.FRAMEBUFFER,E)&&I&&pe.drawBuffers(s,E),pe.viewport(R),pe.scissor(Y),pe.setScissorTest(V),Q){let ce=Ee.get(s.texture);m.framebufferTexture2D(m.FRAMEBUFFER,m.COLOR_ATTACHMENT0,m.TEXTURE_CUBE_MAP_POSITIVE_X+S,ce.__webglTexture,w)}else if(ae){let ce=Ee.get(s.texture),Ce=S;m.framebufferTextureLayer(m.FRAMEBUFFER,m.COLOR_ATTACHMENT0,ce.__webglTexture,w,Ce)}else if(s!==null&&w!==0){let ce=Ee.get(s.texture);m.framebufferTexture2D(m.FRAMEBUFFER,m.COLOR_ATTACHMENT0,m.TEXTURE_2D,ce.__webglTexture,w)}p=-1},this.readRenderTargetPixels=function(s,S,w,I,E,Q,ae,de=0){if(!(s&&s.isWebGLRenderTarget)){console.error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not THREE.WebGLRenderTarget.");return}let ce=Ee.get(s).__webglFramebuffer;if(s.isWebGLCubeRenderTarget&&ae!==void 0&&(ce=ce[ae]),ce){pe.bindFramebuffer(m.FRAMEBUFFER,ce);try{let Ce=s.textures[de],be=Ce.format,ge=Ce.type;if(!Xe.textureFormatReadable(be)){console.error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not in RGBA or implementation defined format.");return}if(!Xe.textureTypeReadable(ge)){console.error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not in UnsignedByteType or implementation defined type.");return}S>=0&&S<=s.width-I&&w>=0&&w<=s.height-E&&(s.textures.length>1&&m.readBuffer(m.COLOR_ATTACHMENT0+de),m.readPixels(S,w,I,E,te.convert(be),te.convert(ge),Q))}finally{let Ce=G!==null?Ee.get(G).__webglFramebuffer:null;pe.bindFramebuffer(m.FRAMEBUFFER,Ce)}}},this.readRenderTargetPixelsAsync=async function(s,S,w,I,E,Q,ae,de=0){if(!(s&&s.isWebGLRenderTarget))throw new Error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not THREE.WebGLRenderTarget.");let ce=Ee.get(s).__webglFramebuffer;if(s.isWebGLCubeRenderTarget&&ae!==void 0&&(ce=ce[ae]),ce)if(S>=0&&S<=s.width-I&&w>=0&&w<=s.height-E){pe.bindFramebuffer(m.FRAMEBUFFER,ce);let Ce=s.textures[de],be=Ce.format,ge=Ce.type;if(!Xe.textureFormatReadable(be))throw new Error("THREE.WebGLRenderer.readRenderTargetPixelsAsync: renderTarget is not in RGBA or implementation defined format.");if(!Xe.textureTypeReadable(ge))throw new Error("THREE.WebGLRenderer.readRenderTargetPixelsAsync: renderTarget is not in UnsignedByteType or implementation defined type.");let Ie=m.createBuffer();m.bindBuffer(m.PIXEL_PACK_BUFFER,Ie),m.bufferData(m.PIXEL_PACK_BUFFER,Q.byteLength,m.STREAM_READ),s.textures.length>1&&m.readBuffer(m.COLOR_ATTACHMENT0+de),m.readPixels(S,w,I,E,te.convert(be),te.convert(ge),0);let ze=G!==null?Ee.get(G).__webglFramebuffer:null;pe.bindFramebuffer(m.FRAMEBUFFER,ze);let Je=m.fenceSync(m.SYNC_GPU_COMMANDS_COMPLETE,0);return m.flush(),await so(m,Je,4),m.bindBuffer(m.PIXEL_PACK_BUFFER,Ie),m.getBufferSubData(m.PIXEL_PACK_BUFFER,0,Q),m.deleteBuffer(Ie),m.deleteSync(Je),Q}else throw new Error("THREE.WebGLRenderer.readRenderTargetPixelsAsync: requested read bounds are out of range.")},this.copyFramebufferToTexture=function(s,S=null,w=0){let I=Math.pow(2,-w),E=Math.floor(s.image.width*I),Q=Math.floor(s.image.height*I),ae=S!==null?S.x:0,de=S!==null?S.y:0;Ue.setTexture2D(s,0),m.copyTexSubImage2D(m.TEXTURE_2D,w,0,0,ae,de,E,Q),pe.unbindTexture()};let Or=m.createFramebuffer(),Fr=m.createFramebuffer();this.copyTextureToTexture=function(s,S,w=null,I=null,E=0,Q=null){Q===null&&(E!==0?(ln("WebGLRenderer: copyTextureToTexture function signature has changed to support src and dst mipmap levels."),Q=E,E=0):Q=0);let ae,de,ce,Ce,be,ge,Ie,ze,Je,et=s.isCompressedTexture?s.mipmaps[Q]:s.image;if(w!==null)ae=w.max.x-w.min.x,de=w.max.y-w.min.y,ce=w.isBox3?w.max.z-w.min.z:1,Ce=w.min.x,be=w.min.y,ge=w.isBox3?w.min.z:0;else{let ht=Math.pow(2,-E);ae=Math.floor(et.width*ht),de=Math.floor(et.height*ht),s.isDataArrayTexture?ce=et.depth:s.isData3DTexture?ce=Math.floor(et.depth*ht):ce=1,Ce=0,be=0,ge=0}I!==null?(Ie=I.x,ze=I.y,Je=I.z):(Ie=0,ze=0,Je=0);let Ne=te.convert(S.format),Me=te.convert(S.type),at;S.isData3DTexture?(Ue.setTexture3D(S,0),at=m.TEXTURE_3D):S.isDataArrayTexture||S.isCompressedArrayTexture?(Ue.setTexture2DArray(S,0),at=m.TEXTURE_2D_ARRAY):(Ue.setTexture2D(S,0),at=m.TEXTURE_2D),m.pixelStorei(m.UNPACK_FLIP_Y_WEBGL,S.flipY),m.pixelStorei(m.UNPACK_PREMULTIPLY_ALPHA_WEBGL,S.premultiplyAlpha),m.pixelStorei(m.UNPACK_ALIGNMENT,S.unpackAlignment);let Ve=m.getParameter(m.UNPACK_ROW_LENGTH),vt=m.getParameter(m.UNPACK_IMAGE_HEIGHT),Nt=m.getParameter(m.UNPACK_SKIP_PIXELS),ut=m.getParameter(m.UNPACK_SKIP_ROWS),Xt=m.getParameter(m.UNPACK_SKIP_IMAGES);m.pixelStorei(m.UNPACK_ROW_LENGTH,et.width),m.pixelStorei(m.UNPACK_IMAGE_HEIGHT,et.height),m.pixelStorei(m.UNPACK_SKIP_PIXELS,Ce),m.pixelStorei(m.UNPACK_SKIP_ROWS,be),m.pixelStorei(m.UNPACK_SKIP_IMAGES,ge);let qe=s.isDataArrayTexture||s.isData3DTexture,pt=S.isDataArrayTexture||S.isData3DTexture;if(s.isDepthTexture){let ht=Ee.get(s),st=Ee.get(S),ct=Ee.get(ht.__renderTarget),En=Ee.get(st.__renderTarget);pe.bindFramebuffer(m.READ_FRAMEBUFFER,ct.__webglFramebuffer),pe.bindFramebuffer(m.DRAW_FRAMEBUFFER,En.__webglFramebuffer);for(let Ct=0;Ct<ce;Ct++)qe&&(m.framebufferTextureLayer(m.READ_FRAMEBUFFER,m.COLOR_ATTACHMENT0,Ee.get(s).__webglTexture,E,ge+Ct),m.framebufferTextureLayer(m.DRAW_FRAMEBUFFER,m.COLOR_ATTACHMENT0,Ee.get(S).__webglTexture,Q,Je+Ct)),m.blitFramebuffer(Ce,be,ae,de,Ie,ze,ae,de,m.DEPTH_BUFFER_BIT,m.NEAREST);pe.bindFramebuffer(m.READ_FRAMEBUFFER,null),pe.bindFramebuffer(m.DRAW_FRAMEBUFFER,null)}else if(E!==0||s.isRenderTargetTexture||Ee.has(s)){let ht=Ee.get(s),st=Ee.get(S);pe.bindFramebuffer(m.READ_FRAMEBUFFER,Or),pe.bindFramebuffer(m.DRAW_FRAMEBUFFER,Fr);for(let ct=0;ct<ce;ct++)qe?m.framebufferTextureLayer(m.READ_FRAMEBUFFER,m.COLOR_ATTACHMENT0,ht.__webglTexture,E,ge+ct):m.framebufferTexture2D(m.READ_FRAMEBUFFER,m.COLOR_ATTACHMENT0,m.TEXTURE_2D,ht.__webglTexture,E),pt?m.framebufferTextureLayer(m.DRAW_FRAMEBUFFER,m.COLOR_ATTACHMENT0,st.__webglTexture,Q,Je+ct):m.framebufferTexture2D(m.DRAW_FRAMEBUFFER,m.COLOR_ATTACHMENT0,m.TEXTURE_2D,st.__webglTexture,Q),E!==0?m.blitFramebuffer(Ce,be,ae,de,Ie,ze,ae,de,m.COLOR_BUFFER_BIT,m.NEAREST):pt?m.copyTexSubImage3D(at,Q,Ie,ze,Je+ct,Ce,be,ae,de):m.copyTexSubImage2D(at,Q,Ie,ze,Ce,be,ae,de);pe.bindFramebuffer(m.READ_FRAMEBUFFER,null),pe.bindFramebuffer(m.DRAW_FRAMEBUFFER,null)}else pt?s.isDataTexture||s.isData3DTexture?m.texSubImage3D(at,Q,Ie,ze,Je,ae,de,ce,Ne,Me,et.data):S.isCompressedArrayTexture?m.compressedTexSubImage3D(at,Q,Ie,ze,Je,ae,de,ce,Ne,et.data):m.texSubImage3D(at,Q,Ie,ze,Je,ae,de,ce,Ne,Me,et):s.isDataTexture?m.texSubImage2D(m.TEXTURE_2D,Q,Ie,ze,ae,de,Ne,Me,et.data):s.isCompressedTexture?m.compressedTexSubImage2D(m.TEXTURE_2D,Q,Ie,ze,et.width,et.height,Ne,et.data):m.texSubImage2D(m.TEXTURE_2D,Q,Ie,ze,ae,de,Ne,Me,et);m.pixelStorei(m.UNPACK_ROW_LENGTH,Ve),m.pixelStorei(m.UNPACK_IMAGE_HEIGHT,vt),m.pixelStorei(m.UNPACK_SKIP_PIXELS,Nt),m.pixelStorei(m.UNPACK_SKIP_ROWS,ut),m.pixelStorei(m.UNPACK_SKIP_IMAGES,Xt),Q===0&&S.generateMipmaps&&m.generateMipmap(at),pe.unbindTexture()},this.copyTextureToTexture3D=function(s,S,w=null,I=null,E=0){return ln('WebGLRenderer: copyTextureToTexture3D function has been deprecated. Use "copyTextureToTexture" instead.'),this.copyTextureToTexture(s,S,w,I,E)},this.initRenderTarget=function(s){Ee.get(s).__webglFramebuffer===void 0&&Ue.setupRenderTarget(s)},this.initTexture=function(s){s.isCubeTexture?Ue.setTextureCube(s,0):s.isData3DTexture?Ue.setTexture3D(s,0):s.isDataArrayTexture||s.isCompressedArrayTexture?Ue.setTexture2DArray(s,0):Ue.setTexture2D(s,0),pe.unbindTexture()},this.resetState=function(){P=0,y=0,G=null,pe.reset(),Pe.reset()},typeof __THREE_DEVTOOLS__<"u"&&__THREE_DEVTOOLS__.dispatchEvent(new CustomEvent("observe",{detail:this}))}get coordinateSystem(){return co}get outputColorSpace(){return this._outputColorSpace}set outputColorSpace(n){this._outputColorSpace=n;let t=this.getContext();t.drawingBufferColorSpace=tt._getDrawingBufferColorSpace(n),t.unpackColorSpace=tt._getUnpackColorSpace()}};export{Qr as ACESFilmicToneMapping,Kt as AddEquation,ta as AddOperation,kf as AdditiveAnimationBlendMode,di as AdditiveBlending,Zr as AgXToneMapping,qa as AlphaFormat,ka as AlwaysCompare,Vn as AlwaysDepth,zf as AlwaysStencilFunc,Wf as AmbientLight,Xf as AnimationAction,Kf as AnimationClip,Yf as AnimationLoader,qf as AnimationMixer,$f as AnimationObjectGroup,Zf as AnimationUtils,Qf as ArcCurve,eo as ArrayCamera,Jf as ArrowHelper,jf as AttachedBindMode,ed as Audio,td as AudioAnalyser,nd as AudioContext,id as AudioListener,rd as AudioLoader,ad as AxesHelper,mt as BackSide,od as BasicDepthPacking,sd as BasicShadowMap,cd as BatchedMesh,ld as Bone,fd as BooleanKeyframeTrack,dd as Box2,ud as Box3,pd as Box3Helper,lr as BoxGeometry,hd as BoxHelper,cn as BufferAttribute,hr as BufferGeometry,md as BufferGeometryLoader,Ka as ByteType,_d as Cache,vd as Camera,gd as CameraHelper,Sd as CanvasTexture,Ed as CapsuleGeometry,Md as CatmullRomCurve3,Jr as CineonToneMapping,Td as CircleGeometry,ya as ClampToEdgeWrapping,xd as Clock,$e as Color,Ad as ColorKeyframeTrack,tt as ColorManagement,Rd as CompressedArrayTexture,Cd as CompressedCubeTexture,bd as CompressedTexture,Pd as CompressedTextureLoader,Ld as ConeGeometry,ha as ConstantAlphaFactor,_a as ConstantColorFactor,Ud as Controls,Dd as CubeCamera,Qt as CubeReflectionMapping,kt as CubeRefractionMapping,Xr as CubeTexture,wd as CubeTextureLoader,mn as CubeUVReflectionMapping,Id as CubicBezierCurve,yd as CubicBezierCurve3,Nd as CubicInterpolant,ci as CullFaceBack,La as CullFaceFront,Od as CullFaceFrontBack,Pa as CullFaceNone,Fd as Curve,Bd as CurvePath,Ua as CustomBlending,qr as CustomToneMapping,Gd as CylinderGeometry,Hd as Cylindrical,Kr as Data3DTexture,mr as DataArrayTexture,Vd as DataTexture,kd as DataTextureLoader,zd as DataUtils,Wd as DecrementStencilOp,Xd as DecrementWrapStencilOp,Kd as DefaultLoadingManager,Qn as DepthFormat,un as DepthStencilFormat,vr as DepthTexture,Yd as DetachedBindMode,qd as DirectionalLight,$d as DirectionalLightHelper,Zd as DiscreteInterpolant,Qd as DodecahedronGeometry,Mt as DoubleSide,Ma as DstAlphaFactor,Ta as DstColorFactor,Jd as DynamicCopyUsage,jd as DynamicDrawUsage,eu as DynamicReadUsage,tu as EdgesGeometry,nu as EllipseCurve,Ha as EqualCompare,Gn as EqualDepth,iu as EqualStencilFunc,yn as EquirectangularReflectionMapping,Nn as EquirectangularRefractionMapping,fr as Euler,ja as EventDispatcher,ru as ExtrudeGeometry,au as FileLoader,ou as Float16BufferAttribute,su as Float32BufferAttribute,Dt as FloatType,cu as Fog,lu as FogExp2,fu as FramebufferTexture,Zt as FrontSide,Mr as Frustum,du as FrustumArray,uu as GLBufferAttribute,pu as GLSL1,si as GLSL3,Ba as GreaterCompare,Fn as GreaterDepth,Ga as GreaterEqualCompare,Bn as GreaterEqualDepth,hu as GreaterEqualStencilFunc,mu as GreaterStencilFunc,_u as GridHelper,vu as Group,_n as HalfFloatType,gu as HemisphereLight,Su as HemisphereLightHelper,Eu as IcosahedronGeometry,Mu as ImageBitmapLoader,Tu as ImageLoader,xu as ImageUtils,Au as IncrementStencilOp,Ru as IncrementWrapStencilOp,Cu as InstancedBufferAttribute,bu as InstancedBufferGeometry,Pu as InstancedInterleavedBuffer,Lu as InstancedMesh,Uu as Int16BufferAttribute,Du as Int32BufferAttribute,wu as Int8BufferAttribute,pr as IntType,Iu as InterleavedBuffer,yu as InterleavedBufferAttribute,Nu as Interpolant,Ou as InterpolateDiscrete,Fu as InterpolateLinear,Bu as InterpolateSmooth,Gu as InterpolationSamplingMode,Hu as InterpolationSamplingType,Vu as InvertStencilOp,ku as KeepStencilOp,zu as KeyframeTrack,Wu as LOD,Xu as LatheGeometry,sa as Layers,Va as LessCompare,Hn as LessDepth,_r as LessEqualCompare,dn as LessEqualDepth,Ku as LessEqualStencilFunc,Yu as LessStencilFunc,qu as Light,$u as LightProbe,Zu as Line,Qu as Line3,Ju as LineBasicMaterial,ju as LineCurve,ep as LineCurve3,tp as LineDashedMaterial,np as LineLoop,ip as LineSegments,Bt as LinearFilter,rp as LinearInterpolant,ap as LinearMipMapLinearFilter,op as LinearMipMapNearestFilter,Yt as LinearMipmapLinearFilter,Mn as LinearMipmapNearestFilter,vn as LinearSRGBColorSpace,ea as LinearToneMapping,Er as LinearTransfer,sp as Loader,cp as LoaderUtils,lp as LoadingManager,fp as LoopOnce,dp as LoopPingPong,up as LoopRepeat,pp as MOUSE,hp as Material,mp as MaterialLoader,_p as MathUtils,vp as Matrix2,Oe as Matrix3,Vt as Matrix4,wa as MaxEquation,xt as Mesh,Vr as MeshBasicMaterial,ca as MeshDepthMaterial,fa as MeshDistanceMaterial,gp as MeshLambertMaterial,Sp as MeshMatcapMaterial,Ep as MeshNormalMaterial,Mp as MeshPhongMaterial,Tp as MeshPhysicalMaterial,xp as MeshStandardMaterial,Ap as MeshToonMaterial,Da as MinEquation,Ia as MirroredRepeatWrapping,na as MixOperation,li as MultiplyBlending,ia as MultiplyOperation,$t as NearestFilter,Rp as NearestMipMapLinearFilter,Cp as NearestMipMapNearestFilter,nn as NearestMipmapLinearFilter,Oa as NearestMipmapNearestFilter,$r as NeutralToneMapping,za as NeverCompare,kn as NeverDepth,bp as NeverStencilFunc,wt as NoBlending,Ft as NoColorSpace,At as NoToneMapping,Pp as NormalAnimationBlendMode,fn as NormalBlending,Fa as NotEqualCompare,On as NotEqualDepth,Lp as NotEqualStencilFunc,Up as NumberKeyframeTrack,Dp as Object3D,wp as ObjectLoader,oa as ObjectSpaceNormalMap,Ip as OctahedronGeometry,Ca as OneFactor,pa as OneMinusConstantAlphaFactor,ma as OneMinusConstantColorFactor,va as OneMinusDstAlphaFactor,ga as OneMinusDstColorFactor,Sa as OneMinusSrcAlphaFactor,Ea as OneMinusSrcColorFactor,Hr as OrthographicCamera,Sr as PCFShadowMap,Yr as PCFSoftShadowMap,hn as PMREMGenerator,yp as Path,sn as PerspectiveCamera,Br as Plane,dr as PlaneGeometry,Np as PlaneHelper,Op as PointLight,Fp as PointLightHelper,Bp as Points,Gp as PointsMaterial,Hp as PolarGridHelper,Vp as PolyhedronGeometry,kp as PositionalAudio,zp as PropertyBinding,Wp as PropertyMixer,Xp as QuadraticBezierCurve,Kp as QuadraticBezierCurve3,Yp as Quaternion,qp as QuaternionKeyframeTrack,$p as QuaternionLinearInterpolant,Fi as RED_GREEN_RGTC2_Format,Ja as RED_RGTC1_Format,ro as REVISION,la as RGBADepthPacking,Tt as RGBAFormat,Cr as RGBAIntegerFormat,Di as RGBA_ASTC_10x10_Format,Pi as RGBA_ASTC_10x5_Format,Li as RGBA_ASTC_10x6_Format,Ui as RGBA_ASTC_10x8_Format,wi as RGBA_ASTC_12x10_Format,Ii as RGBA_ASTC_12x12_Format,Ei as RGBA_ASTC_4x4_Format,Mi as RGBA_ASTC_5x4_Format,Ti as RGBA_ASTC_5x5_Format,xi as RGBA_ASTC_6x5_Format,Ai as RGBA_ASTC_6x6_Format,Ri as RGBA_ASTC_8x5_Format,Ci as RGBA_ASTC_8x6_Format,bi as RGBA_ASTC_8x8_Format,Cn as RGBA_BPTC_Format,Si as RGBA_ETC2_EAC_Format,_i as RGBA_PVRTC_2BPPV1_Format,mi as RGBA_PVRTC_4BPPV1_Format,xn as RGBA_S3TC_DXT1_Format,An as RGBA_S3TC_DXT3_Format,Rn as RGBA_S3TC_DXT5_Format,Zp as RGBDepthPacking,$a as RGBFormat,Qp as RGBIntegerFormat,yi as RGB_BPTC_SIGNED_Format,Ni as RGB_BPTC_UNSIGNED_Format,vi as RGB_ETC1_Format,gi as RGB_ETC2_Format,hi as RGB_PVRTC_2BPPV1_Format,pi as RGB_PVRTC_4BPPV1_Format,Tn as RGB_S3TC_DXT1_Format,Jp as RGDepthPacking,Qa as RGFormat,Rr as RGIntegerFormat,jp as RawShaderMaterial,eh as Ray,th as Raycaster,nh as RectAreaLight,Za as RedFormat,Ar as RedIntegerFormat,jr as ReinhardToneMapping,ih as RenderTarget,rh as RenderTarget3D,Na as RepeatWrapping,ah as ReplaceStencilOp,da as ReverseSubtractEquation,oh as RingGeometry,Bi as SIGNED_RED_GREEN_RGTC2_Format,Oi as SIGNED_RED_RGTC1_Format,io as SRGBColorSpace,Ye as SRGBTransfer,sh as Scene,De as ShaderChunk,gt as ShaderLib,It as ShaderMaterial,ch as ShadowMaterial,lh as Shape,fh as ShapeGeometry,dh as ShapePath,uh as ShapeUtils,Ya as ShortType,ph as Skeleton,hh as SkeletonHelper,mh as SkinnedMesh,_h as Source,vh as Sphere,gh as SphereGeometry,Sh as Spherical,Eh as SphericalHarmonics3,Mh as SplineCurve,Th as SpotLight,xh as SpotLightHelper,Ah as Sprite,Rh as SpriteMaterial,Aa as SrcAlphaFactor,xa as SrcAlphaSaturateFactor,Ra as SrcColorFactor,Ch as StaticCopyUsage,bh as StaticDrawUsage,Ph as StaticReadUsage,Lh as StereoCamera,Uh as StreamCopyUsage,Dh as StreamDrawUsage,wh as StreamReadUsage,Ih as StringKeyframeTrack,ua as SubtractEquation,fi as SubtractiveBlending,yh as TOUCH,aa as TangentSpaceNormalMap,Nh as TetrahedronGeometry,gr as Texture,Oh as TextureLoader,Fh as TextureUtils,Bh as TimestampQuery,Gh as TorusGeometry,Hh as TorusKnotGeometry,Vh as Triangle,kh as TriangleFanDrawMode,zh as TriangleStripDrawMode,Wh as TrianglesDrawMode,Xh as TubeGeometry,Kh as UVMapping,zr as Uint16BufferAttribute,kr as Uint32BufferAttribute,Yh as Uint8BufferAttribute,qh as Uint8ClampedBufferAttribute,$h as Uniform,Zh as UniformsGroup,ne as UniformsLib,ra as UniformsUtils,yt as UnsignedByteType,jt as UnsignedInt248Type,Xa as UnsignedInt5999Type,Jt as UnsignedIntType,Tr as UnsignedShort4444Type,xr as UnsignedShort5551Type,pn as UnsignedShortType,Et as VSMShadowMap,dt as Vector2,We as Vector3,ft as Vector4,Qh as VectorKeyframeTrack,Jh as VideoFrameTexture,jh as VideoTexture,em as WebGL3DRenderTarget,tm as WebGLArrayRenderTarget,co as WebGLCoordinateSystem,Gr as WebGLCubeRenderTarget,zt as WebGLRenderTarget,cr as WebGLRenderer,If as WebGLUtils,nm as WebGPUCoordinateSystem,bn as WebXRController,im as WireframeGeometry,rm as WrapAroundEnding,am as ZeroCurvatureEnding,ba as ZeroFactor,om as ZeroSlopeEnding,sm as ZeroStencilOp,no as createCanvasElement};
/*! Bundled license information:

three/build/three.module.js:
  (**
   * @license
   * Copyright 2010-2025 Three.js Authors
   * SPDX-License-Identifier: MIT
   *)
*/
//# sourceMappingURL=three.mjs.map