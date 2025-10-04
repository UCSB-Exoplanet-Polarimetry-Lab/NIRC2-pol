;+
; NAME:
;   QACITS_NIRC2_PARAMS
;
; PURPOSE:
;   Initialize the parameter values.
;
; CALLING SEQUENCE: qacits_init_params, centerx=centerx,
;   centery=centery, lambdaoverd=lambdaoverd,
;   nirc_account=nirc_account, dpix=dpix, tint_opti=tint_opti,
;   coad_opti=coad_opti, subc_opti=subc_opti, n_opti_max=n_opti_max,
;   tiptilt_opti_min=tiptilt_opti_min, tint_psf=tint_psf , coad_psf
;   =coad_psf, subc_psf=subc_psf, subc_sci=subc_sci, quad_width_pix =
;   quad_width_pix, inner_rad_pix=inner_rad_pix,
;   null_depth_rad_pix=null_depth_rad_pix,
;   estimator_type=estimator_type, gam_in=gam_in, gam_out=gam_out,
;   tt_limit=tt_limit, gain=gain, deadband=deadband, pws=pws,
;   modPos=modPos, rangeX=rangeX, rangeY=rangeY
;
; DESCRIPTION:
;   This procedure allows the initialization of the parameter values using keywords. 
;   In particular the directory for the data storage should be specified, along with 
;   the acquisition settings (for each acqusition type: off-axis psf and optimization 
;   mode) and QACITS parameter.
;   Some parameters are not used directly in the algorithm but should be specified by 
;   the users in the routine text, in particular:
;   plate_scale         : pixel size [mas] 
;   lambdaoverd_arc     : lambda over D [arcsec] (depends on wavelength and telescope diameter)
;   quad_width          : quadrant width [lamdba/D]
;   inner_rad           : radius of the central circle used for the inner estimator [lambda/D]
;   null_depth_rad      : radius of the circle used to estimate the null depth [lambda/D]
;   
;
; INPUT VARIABLES:
;   centerx             : approximate x position of the vortex center [pixels] (in the 1024x1024 frame)
;   centery             : approximate y position of the vortex center [pixels] (in the 1024x1024 frame)
;   data_dir            : directory containing the data, including the complete path [string]
;   dpix                : offset [pixels] applied to acquire the off-axis PSF
;   n_opti_max          : maximum number of iteration for the optimization seq
;   tiptilt_opti_min    : maximal incremental tiptilt accepted for stable regime [lambda/D]
;   tt_modulus_max      : maximal tiptilt modulus accepted for stable regime [lambda/D]
;   stab_criterion      : minimal nb of optimization iterations with low tip-tilt variation needed for stability
;   tint_opti           : integration time for the optimization mode [seconds]
;   coad_opti           : number of coadds for the optimization mode [integer]
;   subc_opti           : width of the sub-frame for the optimization mode [pixels] (typically 1024, 512, 256)
;   tint_psf            : integratioin time for the off-axis PSF [seconds]. If set to 0, it will 
;                         force the lower integration time
;   coad_psf            : number of coadds for the off-axis PSF acquisition [integer]
;   subc_psf            : width of the sub-frame for the off-axis PSF
;                         acquisition [pixels] (typically 1024, 512, 256)
;   subc_sci            : width of the sub-frame for the science acquisition sequence [pixels] 
;                         (typically 1024, 512, 256)
;   lambdaoverd         : lambda over D [pixels]
;   gam_in              : QACITS proportionnal factor used for the estimator using the inner region of the image
;   gam_out             : QACITS proportionnal factor used for the estimator using the outer region of the image
;   estimator_type      : QACITS estimator type ('both_revsign'/'both_simple'/'both_outonly'/'inner_only' 
;                         or 'outer_only')
;   quad_width_pix      : quadrant width [pixels]
;   inner_rad_pix       : radius of the central circle used for the inner estimator [pixels]
;   null_depth_rad_pix  : radius of the circle used to estimate the null depth [pixels]
;   gain                : loop gain
;   deadband            : deadband [lambda/D] (no correction applied if the estimated tiptilt is
;                         lower than deadband)
;   tt_limit            : threshold for switching to small tiptilt regime [lambda/D]
;   pws                 : set this keyword to use the routine for PWS 
;   modPos              : outputs modulator mirror position in modulator command unit: [x, y] 
;   rangeX              : outputs range of the modulator in X in modulator command unit - [-ve, +ve] range
;   rangeY              : outputs range of the modulator in Y in modulator command unit - [-ve, +ve] range
;
; OUTPUTS:
;   none
;
; DEPENDENCIES:
;   NIRC2_GET_MODRANGE
;
; MODIFICATION HISTORY:
;   Version 1.0, 28-JUL-2015, by Elsa Huby / Olivier Absil, Université de Liège (elsa.huby@ulg.ac.be)
;   Version 1.1, 20-SEP-2015, EH: added the parameter nirc_account to be defined for observation nights.
;   Version 1.2, 17-DEC-2015, EH: added the parameters for the integral controller
;   Version 1.3, 23-DEC-2018: S. Ragland updated the routine for PWS
;                             through a keyword, 'pws'
;   2019-OCT-13, CAAI: Defined subc_ref, subc_psf, def_subc_opti, subc_sci and
;                      dpix as two-element arrays.
;   2019-OCT-19, S. Ragland deleted the offline keyword
;   2020-MAY-27, CAAI: Enabling faint_tint_psf in PyWFS mode.
;   2025-OCT-02, B. Lewis adjusted center values for NIRC2 polarimetry with Wollaston beamsplitter
;-

pro qacits_nirc2_params, centerx=centerx, centery=centery, subc_ref=subc_ref, $
                         plate_scale=plate_scale, lambdaoverd=lambdaoverd, $
                         dpix=dpix, tint_opti=tint_opti, coad_opti=coad_opti, subc_opti=subc_opti, $
                         n_opti_max=n_opti_max, tt_modulus_max=tt_modulus_max, n_stability_min=n_stability_min, $
                         tint_psf=tint_psf, coad_psf=coad_psf, subc_psf=subc_psf, faint_tint_psf=faint_tint_psf, $
                         subc_sci=subc_sci, quad_width_pix=quad_width_pix, inner_rad_pix=inner_rad_pix, $
                         null_depth_rad_pix=null_depth_rad_pix,  wavelength=wavelength, $
                         estimator_type=estimator_type, gam_in=gam_in, gam_out=gam_out, tt_limit=tt_limit, $
                         gain=gain, deadband=deadband,  integral_gain=integral_gain, $
                         maximum_integrator=maximum_integrator, maxi_correction=maxi_correction, $
                         cxy_psf = cxy_psf, def_tint_opti=def_tint_opti, def_coad_opti=def_coad_opti, $
                         def_subc_opti=def_subc_opti, subwindow_width=subwindow_width, $
                         pws=pws, modPos=modPos, modAmp=modAmp, rangeX=rangeX, rangeY=rangeY, $
                         band=band, data_dir=data_dir, skip=skip


;*** Rough position of the vortex center ***
;--- (will be systematically fitted at the beginning of each procedure) ---
;if not (keyword_set(centerx)) then begin 
   case strupcase(band) of
      'K': begin
         subc_ref         = [1024, 1024] ; window size for reference frame used 
                                         ; to define the the vortex center coordinates
;         centerx          = 534          ; approximate x vortex center position (2019-10-12)
;         centery          = 557          ; approximate y vortex center position (2019-10-12)
;         centerx          = 525          ; approximate x vortex center position (2019-10-20)
;         centery          = 544          ; approximate y vortex center position (2019-10-20)
         centerx          = 326          ; approximate x vortex center position Wollaston upper beam (2025-10-02)
         centery          = 696          ; approximate y vortex center position Wollaston upper beam (2025-10-02)

      end
      'L': begin
         MESSAGE, 'Warning: We have not yet recorded the vortex center shift with the Wollaston in L band; this procedure will likely fail.'
         subc_ref         = [1024, 1024] ; window size for reference frame used 
                                         ; to define the the vortex center coordinates
         centerx          = 542          ; approximate x vortex center position
         centery          = 497          ; approximate y vortex center position
      end
      'M': begin
         MESSAGE, 'Warning: M band is not supported for NIRC2 polarimetry.'
         subc_ref         = [1024, 1024] ; window size for reference frame used 
                                         ; to define the the vortex center coordinates
         centerx          = 541          ; approximate x vortex center position
         centery          = 498          ; approximate y vortex center position
      end
   endcase
;endif else subc_ref         = [1024, 1024] ; window size for reference frame used 

   subwindow_width = 60         ; 2016.08.03 update: half width of the sub-window used to perform
                                ; the 2D-Gaussian fit of the off-axis
                                ; PSF and vortex center.
 
;*** Acquisition settings ***

;--- STAR OFFSET for the off-axis PSF acq ---
;--- this offset will be applied along the vertical axis (using py command) ---
;--- note: positive offset will offset the star downwards on the NIRC2 display ---

; S. Ragland introduced the following piece of code on 2019 Jan 02

   if keyword_set(pws) then begin
   
;      nirc2_get_modrange, rangeXpix, rangeYpix, rangeX=rangeX, rangeY=rangeY, modAmp=modAmp, modPos=modPos
;      dpix=40
;      subc_psf=round(2.0*(centery-subc_ref/2+0.9*subwindow_width))

      ; (+)ve dpix[0] moves the star ? on NIRC2  
      ; (+)ve dpix[1] moves the star up on NIRC2  

      case band of
         'K': begin             ;----- K-BAND -----------------
            dpix = [0, -25]     
            subc_psf=[128, 152]
         end
         'L': begin             ;----- L-BAND -----------------
            dpix = [0, -25]    
            subc_psf=[128, 152]
         end 
         'M': begin             ;----- M-BAND -----------------
            dpix = [0, -25]    
            subc_psf=[128, 152]    
         end
      endcase
      
   endif else begin

      ; (+)ve dpix[0] moves the star left on NIRC2  
      ; (+)ve dpix[1] moves the star down on NIRC2  

      case band of
         'K': begin             ;----- K-BAND -----------------
            dpix = [0, 60]     
            subc_psf=[128, 152]   
         end
         'L': begin             ;----- L-BAND -----------------
            dpix = [35, -35]        
            subc_psf=[128, 152]
         end 
         'M': begin             ;----- M-BAND -----------------
            dpix = [35, -35]        
            subc_psf=[128, 152]
         end
      endcase

   endelse

;--- OFF-AXIS PSF ACQUISITION ---

   case strupcase(band) of

      ; 2020-05-27 - CAAI: Commented out "if not keyword_set(pws)"
      
      'K': begin                ;----- K-BAND -----------------
         tint_psf = 0  ; zero value will force the lower integration time (0.005 s for subc=128)
         coad_psf = 100 ; numbr of coadds
                                ; S. Ragland modified the following line on 2019 Jan 02
         ;if not keyword_set(pws) then begin
            faint_tint_psf = 0.01 ; integration time for faint targets
         ;endif
      end
      'L': begin                ;----- L-BAND -----------------
         tint_psf = 0  ; zero value will force the lower integration time (0.005 s for subc=128)
         coad_psf = 100 ; number of coadds
                                ; S. Ragland modified the following line on 2019 Jan 02
         ;if not keyword_set(pws) then begin
            faint_tint_psf = 0.02 ; integration time for faint targets
         ;endif
      end 
      'M': begin                ;----- M-BAND -----------------
         tint_psf = 0  ; zero value will force the lower integration time (0.005 s for subc=128)
         coad_psf = 100 ; number of coadds
                                ; S. Ragland modified the following line on 2019 Jan 02
         ;if not keyword_set(pws) then begin
            faint_tint_psf = 0.01 ; integration time for faint targets
         ;endif
      end
   endcase

;--- DEFAULT OPTIMIZATION ACQ SETTINGS ---

   case strupcase(band) of
      'K': begin                ;----- K-BAND -----------------
         def_tint_opti     = 0.1
         def_coad_opti     = 10
         def_subc_opti     = [512, 512]
      end
      'L': begin                ;-----L-BAND -----------------
         def_tint_opti     = 0.2
         def_coad_opti     = 10
         def_subc_opti     = [512, 512]
      end
      'M': begin                ;----- M-BAND -----------------
         def_tint_opti     = 0.1
         def_coad_opti     = 10
         def_subc_opti     = [512, 512]
      end
   endcase

;--- SCIENCE ACQUISITION SEQUENCE

if not keyword_set(subc_sci) then begin
   case strupcase(band) of
      'K': subc_sci     = [1024, 1024]
      'L': subc_sci     = [1024, 1024]
      'M': subc_sci     = [512, 512]
   endcase
endif 

;*** Corresponding rough position of the off-axis PSF center ***
;--- (will be systematically fitted at the beginning of each procedure) ---
;--- /!\ the coordinate system is set in the sub-frame defined by subc_psf

cxy_psf = [centerx-(subc_ref[0]-subc_psf[0])/2.-dpix[0], centery-(subc_ref[1]-subc_psf[1])/2.-dpix[1]]

print, 'centerx, centery: ', centerx, centery
print, 'subc_psf: ', subc_psf
print, 'subc_ref: ', subc_ref
print, 'cxy_psf: ', cxy_psf
print, 'dpix: ', dpix
print, ''
 
 
if total(cxy_psf lt 0) ge 1 then begin
   message, 'WARNING: offset of the PSF is incompatible with the chosen subc_psf: the PSF is out of the frame.'
endif

;*** Image properties ***

   plate_scale         = 9.971                                     ;-- mas
   telescope_diam      = 10.9299                                   ;-- m
   lambdaoverd_arc     = wavelength/telescope_diam * 180./!dpi * 3600 ;-- lambda over D in arcsec
   lambdaoverd         = lambdaoverd_arc/plate_scale * 1000           ;-- lambda over D in pixels

;*** QACITS Parameters ***

;-- MODEL PARAMETERS
   gam_in              =  -0.10 ;-- prop factor for inner region
   gam_out             =  0.085 ;-- prop factor for outer region
   
;-- REGIONS OF INTEREST
   estimator_type      = 'outer_only'  
;-- possible estimator types: 'outer_only', 'inner_only', 'both_keck'
   quad_width          = 3.5    ;-- quadrant width in lamdba over D
   inner_rad           = 2.     ;-- inner circle radius in lambda over D
   null_depth_rad      = 2.     ;-- radius of the circle where the null depth is computed

;-- Conversion in pixels
   quad_width_pix      = quad_width * lambdaoverd  ;-- quadrant width in pixels
   inner_rad_pix       = inner_rad * lambdaoverd   ;-- radius in pixels
   null_depth_rad_pix  = null_depth_rad * lambdaoverd ;-- null_depth_rad * lambdaoverd

;-- LOOP PARAMETERS
   if keyword_set(pws) then begin
      gain                = 0.3 ;-- Proportionnal gain
      integral_gain       = 0.1 ;-- Integral gain
      deadband            = 0.05 ;-- Deadband in lambda/D
      maximum_integrator  = .008
      maxi_correction     = .07
      tt_limit            = 0.2 ;-- in lbd/D, threshold for switching to small tiptilt regime
   endif else begin
      gain                = 0.2 ;-- Proportionnal gain
      integral_gain       = 0.1 ;-- Integral gain
      deadband            = 0.05 ;-- Deadband in lambda/D
      maximum_integrator  = .008
      maxi_correction     = .07
      tt_limit            = 0.2 ;-- in lbd/D, threshold for switching to small tiptilt regime
   endelse

;--- Optimization SEQUENCE ---
   n_opti_max        = 3        ;-- maximum number of iteration for the optimization seq
   tt_modulus_max    = .1       ;-- maximal tiptilt modulus accepted for stable regime
   n_stability_min   = 2        ;-- minimal nb of low tip-tilt variation needed for stability
end
